# terraform-aws-ekai

Self-service Terraform for deploying Ekai into **your own AWS account**. Two
`terraform apply` runs provision the VPC, an EKS cluster, RDS (PostgreSQL),
in-cluster Redis/Neo4j, ArgoCD, and deploy the `ekai-saas` Helm chart —
everything needed for a working Ekai install end to end.

This repo has 2 layers:

- **The modules** — the repo root (this directory) and `cicd/` are plain,
  reusable Terraform modules: no `backend` block, nothing applied directly.
  The repo root wires up the `bootstrap`, `cluster`, and `platform`
  submodules into one apply's worth of resources; `cicd/` wires up
  `modules/cicd` (the customer secret, ExternalSecrets, IRSA, and the
  ArgoCD Application that actually deploys the app).
- **The root configs** — `examples/self-deploy/root/` and
  `examples/self-deploy/cicd/` are the actual state-holding configs that
  call those two modules and get applied. `examples/self-deploy/cicd/`
  reads `examples/self-deploy/root/`'s state via `terraform_remote_state`.

Why 2 applies and not 1: the ArgoCD Terraform provider's `password` field
has to be a value Terraform already knows *before* it starts applying — it
can't be a same-apply resource's computed attribute (unlike the
kubernetes/helm/kubectl providers, whose `exec`-based auth is specifically
designed to defer until first use). The root config generates that
password; `cicd/` has to run afterward, as its own apply, to read it back
safely. See `cicd/main.tf`'s header comment for the full explanation.

## Prerequisites

- An AWS account you have admin rights in (to bootstrap the scoped IAM user
  Terraform actually runs as — see Step 1 of `scripts/self-deploy.sh`)
- [AWS CLI](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html),
  configured (`aws configure`) with that admin identity
- [Terraform](https://developer.hashicorp.com/terraform/install) >= 1.9
- `jq`, `htpasswd` (from `apache2-utils`/`httpd-tools`), `openssl`
- A domain you can either delegate a subdomain of to Route53, or that
  already has a Route53 hosted zone

## Quick start (recommended — one command)

```bash
cp env/customer.tfvars env/<name>.tfvars
# edit env/<name>.tfvars — at minimum: region, env, dns_zone

./scripts/self-deploy.sh <name>
```

`self-deploy.sh` creates the scoped IAM user Terraform needs, generates and
saves credentials, then runs both `terraform apply`s for you (in
`examples/self-deploy/root/`, then `examples/self-deploy/cicd/`) after one
confirmation (it creates real, billable AWS resources). See the script's own
header comment for exactly what each step does. This is the one command
most clients need — everything below is either what it does under the hood
or an alternative for advanced use cases.

After both applies, check the outputs for the ArgoCD URL/password and
Route53 nameservers (root) and the portal URL and customer secret's ARN
(cicd):

```bash
terraform output -C examples/self-deploy/root
terraform output -C examples/self-deploy/cicd
```

Fill in the `REPLACE_ME` placeholders in the customer secret (LLM API keys,
Cognito, an IAM user with S3/SES access — see
`terraform output -C examples/self-deploy/cicd client_iam_policy_for_secret_placeholders`)
before the app is fully usable.

## Manual deploy (without self-deploy.sh)

```bash
./scripts/init-state-backend.sh <name>

cd examples/self-deploy/root
terraform init -backend-config=../../../env/backend-<name>.tfbackend
terraform apply -var-file=../../../env/<name>.tfvars

cd ../cicd
terraform init -backend-config=../../../env/backend-<name>-cicd.tfbackend
terraform apply -var-file=../../../env/<name>.tfvars
```

## Using this as a Terraform Registry module (advanced)

The repo root and `cicd/` are structured as ordinary Terraform modules, so
once this repo is connected to the Terraform Registry (a one-time manual
step someone with access to the registry/repo settings has to do — publish
the repo, then push a semver tag; **this does not work until that's been
done**), you can consume them directly instead of using
`examples/self-deploy/`:

```hcl
module "infra" {
  source  = "registry.terraform.io/ekai-ai/ekai/aws"
  version = "~> 1.0"

  region = "us-east-1"
  env    = "acme"
  # ...every variable in variables.tf
}

module "cicd" {
  source  = "registry.terraform.io/ekai-ai/ekai/aws//cicd"
  version = "~> 1.0"
  # ...every variable in cicd/variables.tf, plus the values module.infra
  # exports that cicd needs (see examples/self-deploy/cicd/main.tf for
  # exactly which — with a registry module you'd normally wire these with
  # module.infra.X directly if both modules live in the same config, instead
  # of examples/self-deploy's terraform_remote_state indirection, which only
  # exists because self-deploy.sh's 2-apply split needs an actual state
  # boundary between them)
}
```

`examples/self-deploy/` is the reference implementation of exactly this
pattern (plus the backend/provider wiring a real deployment needs) — read it
before writing your own.

## Tearing down

```bash
./scripts/self-deploy-destroy.sh <name>
```

Runs `terraform destroy` in `examples/self-deploy/cicd/` first (it needs the
cluster/ArgoCD from the root apply still live to clean up against), then in
`examples/self-deploy/root/` — with a retry + VPC-orphan cleanup pass if
that second destroy hits a dependency error (ALBs/ENIs the AWS Load Balancer
Controller hasn't finished releasing yet). Then offers to clean up the S3
state bucket, per-service secrets, and the IAM user `self-deploy.sh`
created.

## Layout

```
main.tf / variables.tf / outputs.tf / providers.tf   # "infra" module (bootstrap+cluster+platform) — no backend, not applied directly
cicd/
  main.tf / variables.tf / outputs.tf / providers.tf  # "cicd" module — no backend, not applied directly
examples/self-deploy/
  root/    # actual root config wrapping the "infra" module — backend + required_providers + module "infra" { source = "../../.." }
  cicd/    # actual root config wrapping the "cicd" module — backend + required_providers + module "cicd" { source = "../../../cicd" }
modules/
  bootstrap/   # Route53 zone + ACM certificate + VPC
  cluster/     # IAM, EKS, RDS, OIDC provider
  platform/    # ALB controller, ESO, Redis, Neo4j, ArgoCD, KEDA, reloader
  cicd/        # customer secret, ExternalSecret, IRSA, ArgoCD Application, DNS records
  <shared low-level modules used by the above>
env/
  customer.tfvars   # template — copy and fill in; shared by both applies
scripts/
  self-deploy.sh            # IAM setup + both terraform applies, guided
  self-deploy-destroy.sh     # both terraform destroys + optional cleanup
  init-state-backend.sh       # creates the S3 state bucket + both backend configs
  cleanup-vpc.sh / cleanup-aws-env.sh   # helpers used by the above
```

Only the self-service path (`cicd_provider = "none"`) is supported in this
distribution. See the comments in `modules/cicd/main.tf` and each
`variables.tf` if you're wondering why `cicd_provider` still accepts
`"codebuild"`/`"github_actions"` values without them actually doing anything
— those are Ekai-internal deployment paths and their supporting Terraform
modules aren't included here.
