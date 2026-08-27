# Architecture

For how to actually deploy this, see [README.md](README.md). This doc
covers how the repo is structured and why, for anyone modifying it or
consuming it a different way than `self-deploy.sh`.

## Why 2 Terraform applies, not 1

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

To destroy manually: `terraform destroy` in `examples/self-deploy/cicd/`
first (it needs the cluster/ArgoCD from the root apply still live to clean
up against), then in `examples/self-deploy/root/`.

## Using this as a Terraform Registry module

The repo root and `cicd/` are structured as ordinary Terraform modules, so
once this repo is connected to the Terraform Registry (a one-time manual
step someone with access to the registry/repo settings has to do — publish
the repo, then push a semver tag; **this does not work until that's been
done**), you can consume them directly instead of using
`examples/self-deploy/`:

```hcl
module "infra" {
  source  = "registry.terraform.io/ekai-ai/ekai/aws"
  version = "~> 0.1"

  region = "us-east-1"
  env    = "<your-name>"
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

`examples/self-deploy/` is the reference implementation of exactly this
pattern (plus the backend/provider wiring a real deployment needs) — read it
before writing your own. Note that `provider "aws"/"kubernetes"/etc.` are
configured *inside* root/cicd themselves (not left for the consumer to
supply) — that's what makes the kubernetes/helm/kubectl exec-auth pattern
above work at all, but it also means a registry consumer can't override
provider configuration via `providers = {}`.

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

## Scope

Only the self-service path (`cicd_provider = "none"`) is supported in this
distribution. See the comments in `modules/cicd/main.tf` and each
`variables.tf` if you're wondering why `cicd_provider` still accepts
`"codebuild"`/`"github_actions"` values without them actually doing anything
— those are Ekai-internal deployment paths and their supporting Terraform
modules aren't included here.
