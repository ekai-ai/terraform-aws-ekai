# terraform-aws-ekai

Deploy Ekai into **your own AWS account**. One script provisions the VPC, an
EKS cluster, RDS (PostgreSQL), in-cluster Redis/Neo4j, ArgoCD, and the
`ekai-saas` Helm chart — everything needed for a working Ekai install.

For how this repo is structured internally (why there are 2 Terraform
applies, the module layout, the Terraform Registry option), see
[ARCHITECTURE.md](ARCHITECTURE.md). This doc only covers deploying it.

## Prerequisites

- An AWS identity with permission to create one specific IAM user and two
  specific IAM policies — **not full account admin**. See
  [PERMISSIONS.md](PERMISSIONS.md) for the exact, ready-to-attach policy;
  this identity is only used to bootstrap the scoped IAM user Terraform
  actually runs as (Step 1 of `scripts/self-deploy.sh`), never for the
  deploy itself.
- [AWS CLI](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html),
  configured (`aws configure`) with that identity
- [Terraform](https://developer.hashicorp.com/terraform/install) >= 1.9
- `jq`, `htpasswd` (from `apache2-utils`/`httpd-tools`), `openssl`
- A domain you can either delegate a subdomain of to Route53, or that
  already has a Route53 hosted zone

## Deploy

```bash
git clone https://github.com/ekai-ai/terraform-aws-ekai.git
cd terraform-aws-ekai
```

**Required:** edit `env/customer.tfvars` and set at minimum `region`, `env`,
`dns_zone` before continuing — `self-deploy.sh` will not work with the
template's placeholder values. Every variable has a full explanation as an
inline comment in that file; the ones most worth a second look before your
first deploy:

| Variable | What it controls |
|---|---|
| `region` | AWS region everything is created in |
| `env` | Unique name embedded in every resource this creates — must be unique per deployment |
| `dns_zone` | Domain this deploys under (`portal.<dns_zone>`, `argocd.<dns_zone>`, ...) |
| `manage_dns_zone` | `true` if Terraform should create the Route53 zone; `false` + `route53_zone_id` if you already have one |
| `node_instance` / `node_min_size` | Worker node size/count — `c5.xlarge` x3 is the tested minimum for the full app stack |
| `db_instance_class` / `allocated_storage` / `multi_az` | RDS sizing and HA — `multi_az = true` roughly doubles RDS cost |
| `enable_redis` / `enable_neo4j` | Must both be `true` — the app's ERD/KEDA features need them |
| `existing_ecr_base_url` | Where the app's container images are pulled from |
| `helm_chart_repo_url` / `helm_chart_version` | Where the `ekai-saas` Helm chart itself comes from |
| `customer_secret_name` | AWS Secrets Manager secret name holding every app env var (default `ekai-customer`) |

Full reference (every variable, every default): `variables.tf` and
`cicd/variables.tf` — or the Terraform Registry's auto-generated Inputs
page once this is published there (see [ARCHITECTURE.md](ARCHITECTURE.md)).

```bash
./scripts/self-deploy.sh customer
```

The argument to `self-deploy.sh` must match the tfvars filename in `env/`
(without `.tfvars`). Use a real, unique `env` value (not `customer`) if
you're deploying more than once — every AWS resource this creates embeds
`env` in its name, so re-running with the same value modifies the *same*
infrastructure rather than creating a second one.

`self-deploy.sh` creates the scoped IAM user Terraform needs, generates and
saves credentials, then runs both `terraform apply`s for you after one
confirmation (it creates real, billable AWS resources).

## After a successful deploy

The customer secret (`ekai-customer` in AWS Secrets Manager by default —
see `customer_secret_name` in `env/customer.tfvars`) ships with several
`REPLACE_ME` placeholders the app needs real values for. Fill them in with
one command — replace the `...` values below with real ones (an IAM user
with S3/SES access, matching
`terraform output -C examples/self-deploy/cicd client_iam_policy_for_secret_placeholders`,
if one doesn't exist yet):

```bash
aws secretsmanager put-secret-value \
  --secret-id ekai-customer \
  --region <your region> \
  --secret-string "$(aws secretsmanager get-secret-value --secret-id ekai-customer --region <your region> --query SecretString --output text | jq '
    .ANTHROPIC_API_KEY = "sk-ant-..." |
    .OPENAI_API_KEY = "sk-..." |
    .COGNITO_REGION = "..." |
    .COGNITO_USER_POOL_ID = "..." |
    .COGNITO_CLIENT_ID = "..." |
    .AWS_ACCESS_KEY_ID = "..." |
    .AWS_SECRET_ACCESS_KEY = "..." |
    .AWS_SES_FROM_EMAIL = "..." |
    .SEMANTICS__GOOGLE_CLOUD_PROJECT = "..." |
    .SEMANTICS__GCS_DOCAI_PROCESSOR_ID = "..." |
    .SEMANTICS__GCS_INPUT_BUCKET = "..." |
    .SEMANTICS__GCS_OUTPUT_BUCKET = "..."
  ')"
```

Only `AWS_ACCESS_KEY_ID`/`AWS_SECRET_ACCESS_KEY`/`AWS_SES_FROM_EMAIL` are
needed to unblock the invite-email flow; the rest can stay `REPLACE_ME`
until you need those specific features. The app picks up the new secret
automatically within about a minute (ESO syncs it into the cluster,
Reloader restarts the affected pods) — no `terraform apply` needed for
this step.

Optional — check the ArgoCD URL/password, Route53 nameservers, portal URL,
and customer secret's ARN:

```bash
terraform output -C examples/self-deploy/root
terraform output -C examples/self-deploy/cicd
```

## Tearing down

```bash
./scripts/self-deploy-destroy.sh customer
```

Destroys everything this created, with confirmation prompts at each
destructive stage. Safe to re-run if it fails partway.

## Troubleshooting

**`InvalidClientTokenId` / `An error occurred ... The security token
included in the request is invalid` right at the start of the script** —
this means your *base* AWS credentials are broken, before the script even
gets to creating anything. Almost always caused by a stale
`AWS_ACCESS_KEY_ID`/`AWS_SECRET_ACCESS_KEY`/`AWS_SESSION_TOKEN` left
exported in your shell from an earlier, unrelated session (these
environment variables silently override your `~/.aws/credentials` file).
Check and clear them:

```bash
env | grep -i AWS_
unset AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN
aws sts get-caller-identity   # should succeed and show your real identity
```

Then re-run `self-deploy.sh`.
