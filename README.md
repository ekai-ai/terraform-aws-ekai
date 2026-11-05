# terraform-aws-ekai

Deploy Ekai into **your own AWS account**. One script provisions the VPC, an
EKS cluster, RDS (PostgreSQL), in-cluster Redis/Neo4j, ArgoCD, and the
`ekai-saas` Helm chart — everything needed for a working Ekai install.

For how this repo is structured internally (why there are 2 Terraform
applies, the module layout), see [ARCHITECTURE.md](https://github.com/ekai-ai/terraform-aws-ekai/blob/main/ARCHITECTURE.md). This
doc only covers deploying it. Prefer consuming it directly as a module
instead of `self-deploy.sh`? See
[Using this as a Terraform Registry module](#using-this-as-a-terraform-registry-module)
below.

## Prerequisites

- [AWS CLI](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html),
  configured (`aws configure`) — see [PERMISSIONS.md](https://github.com/ekai-ai/terraform-aws-ekai/blob/main/PERMISSIONS.md) for
  exactly what this identity needs
- [Terraform](https://developer.hashicorp.com/terraform/install) >= 1.9
- `jq`, `htpasswd` (from `apache2-utils`/`httpd-tools`), `openssl`
- A domain you can either delegate a subdomain of to Route53, or that
  already has a Route53 hosted zone

## Deploy

```bash
git clone https://github.com/ekai-ai/terraform-aws-ekai.git
cd terraform-aws-ekai
cp env/customer.tfvars env/<name>.tfvars
```

`<name>` is your choice (e.g. client name) — it's both the filename and the
argument to `self-deploy.sh` below. Set `env` inside the file to the same
value. Don't edit `env/customer.tfvars` directly — it's the shared template.

**Required:** edit `env/<name>.tfvars` and set at minimum `region`, `env`,
`dns_zone` — `self-deploy.sh` won't work with placeholder values. Every
variable has an inline comment; worth a second look before your first
deploy:

| Variable | What it controls |
|---|---|
| `region` | AWS region everything is created in |
| `env` | Unique name embedded in every resource this creates — must be unique per deployment |
| `dns_zone` | Domain this deploys under (`portal.<dns_zone>`, `argocd.<dns_zone>`, ...) |

Full reference (every variable, every default): `variables.tf` and
`cicd/variables.tf` — or the Terraform Registry's auto-generated Inputs
page ([registry.terraform.io/modules/ekai-ai/ekai/aws](https://registry.terraform.io/modules/ekai-ai/ekai/aws)),
keeping in mind it may be behind `main` (see [above](#using-this-as-a-terraform-registry-module)).

```bash
./scripts/self-deploy.sh <name>
```

The argument to `self-deploy.sh` must match the tfvars filename in `env/`
(without `.tfvars`) — i.e. whatever you named the copy above. Use a real,
unique `env` value if you're deploying more than once — every AWS resource
this creates embeds `env` in its name, so re-running with the same value
modifies the *same* infrastructure rather than creating a second one.

`self-deploy.sh` creates the scoped IAM user Terraform needs, generates and
saves credentials, then runs both `terraform apply`s for you after one
confirmation (it creates real, billable AWS resources).

## After a successful deploy

The customer secret (`ekai-customer` in AWS Secrets Manager by default —
see `customer_secret_name` in `env/customer.tfvars`) ships with
`AWS_ACCESS_KEY_ID`/`AWS_SECRET_ACCESS_KEY`/`AWS_SES_FROM_EMAIL` set to
`REPLACE_ME` — the app needs real values for these to send signup invite
emails. Fill them in with one command — replace the `...` values below
with real ones (an IAM user with S3/SES access, matching
`terraform output -C examples/self-deploy/cicd client_iam_policy_for_secret_placeholders`,
if one doesn't exist yet):

```bash
aws secretsmanager put-secret-value \
  --secret-id ekai-customer \
  --region <your region> \
  --secret-string "$(aws secretsmanager get-secret-value --secret-id ekai-customer --region <your region> --query SecretString --output text | jq '
    .AWS_ACCESS_KEY_ID = "..." |
    .AWS_SECRET_ACCESS_KEY = "..." |
    .AWS_SES_FROM_EMAIL = "..."
  ')"
```

These three alone unblock the invite-email flow. The app picks up the new
secret automatically within about a minute (ESO syncs it into the cluster,
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
./scripts/self-deploy-destroy.sh <name>
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

**`VcpuLimitExceeded` / node group stuck creating, or the EKS managed node
group's underlying Auto Scaling Group shows an `InsufficientInstanceCapacity`/
quota-related scaling error** — a fresh AWS account's default "Running
On-Demand Standard (A, C, D, H, I, M, R, T, Z) instances" vCPU quota is often
far smaller than this stack's default node sizing needs (every node counts
against it, system and app node groups together). Request a quota increase
in the EC2 console (Service Quotas → Amazon EC2 → the relevant "Running
On-Demand ... instances" quota — usually auto-approved within minutes), or
lower `node_instance`/`node_min_size`/`mode_max_size` in that env's tfvars to
fit the existing quota.

## Using this as a Terraform Registry module

Already published:
[registry.terraform.io/modules/ekai-ai/ekai/aws](https://registry.terraform.io/modules/ekai-ai/ekai/aws).
**The published version can lag behind `main`** — publishing a new one
needs its own semver tag pushed, a separate step from merging to `main`;
check the Registry page's version/date against this repo's own commit
history before assuming it's current.

```hcl
module "infra" {
  source  = "registry.terraform.io/ekai-ai/ekai/aws"
  version = "~> 0.1"

  region = "us-east-1"
  env    = "acme"
  # ...every variable in variables.tf
}

module "cicd" {
  source  = "registry.terraform.io/ekai-ai/ekai/aws//cicd"
  version = "~> 0.1"
  # ...every variable in cicd/variables.tf, plus the values module.infra
  # exports that cicd needs (see examples/self-deploy/cicd/main.tf for
  # exactly which — with a registry module you'd normally wire these with
  # module.infra.X directly if both modules live in the same config, instead
  # of examples/self-deploy's terraform_remote_state indirection, which only
  # exists because self-deploy.sh's 2-apply split needs an actual state
  # boundary between them)
}
```

See [ARCHITECTURE.md](https://github.com/ekai-ai/terraform-aws-ekai/blob/main/ARCHITECTURE.md) for why this is 2 separate applies
and the full module layout.
