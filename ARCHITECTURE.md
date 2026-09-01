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

## Variable reference

Every variable in `variables.tf` and `cicd/variables.tf` — the README's
table only covers the handful worth a second look. `region`/`env`/`dns_zone`
are declared in both files identically (see "Shared across layers" below);
everything else lives in only one.

### Shared across layers (`variables.tf` and `cicd/variables.tf`)

| Variable | Default | What it controls |
|---|---|---|
| `region` | — (required) | AWS region — must match the state bucket region |
| `env` | — (required) | Environment slug (e.g. `client1`, `dev`, `prod`) — used in tags and state key |
| `dns_zone` | — (required) | Domain this deploys under, e.g. `client1.ekai.ai` |
| `secrets_name` | `""` | Legacy master-secret name; ignored when `cicd_provider = "none"` |
| `customer_secret_name` | `"ekai-customer"` | Secrets Manager secret Terraform creates holding every app env var |
| `argocd_ingress_host` | `null` → `argocd.<dns_zone>` | ArgoCD's hostname / the ArgoCD provider's connection target |
| `cicd_provider` | `"none"` | `"none"` (supported) / `"codebuild"` / `"github_actions"` (not functional here) |

### Bootstrap submodule (Route53 zone + ACM certificate + VPC)

| Variable | Default | What it controls |
|---|---|---|
| `eks_cluster_name` | — (required) | Base cluster name — prefix for the full name (`<name>-saas-<env>`), also used to tag subnets for ALB/ELB discovery |
| `manage_dns_zone` | `true` | Terraform creates the Route53 zone; `false` to use an existing one (`route53_zone_id`) |
| `route53_zone_id` | `""` | Pre-existing zone ID, required when `manage_dns_zone = false` |
| `vpc_cidr` | — (required) | CIDR block for the VPC |
| `public_subnet_cidrs` | — (required) | Public subnet CIDRs (ALB + NAT gateway) |
| `private_subnet_cidrs` | — (required) | Private subnet CIDRs (EKS nodes + RDS) — must be the same length as `public_subnet_cidrs`, see the validation error message if not |

### Cluster submodule (IAM, EKS, RDS, OIDC provider)

| Variable | Default | What it controls |
|---|---|---|
| `cluster_version` | `null` → AWS latest | Kubernetes version |
| `node_min_size` | — (required) | Worker node floor / initial desired size |
| `mode_max_size` | — (required) | Worker node ceiling — Cluster Autoscaler scales between the two |
| `node_instance` | — (required) | EC2 instance type for worker nodes |
| `node_ami_type` | `"AL2023_x86_64_STANDARD"` | EKS node AMI type (AL2 is EOL for K8s 1.33+) |
| `node_disk_size` | `80` | Worker node root disk size, GiB |
| `db_instance_class` | — (required) | RDS instance class |
| `engine_version` | — (required) | PostgreSQL engine version — check `aws rds describe-db-engine-versions` if a fresh apply 400s |
| `rds_storage_type` | `"gp2"` | RDS storage type |
| `allocated_storage` | — (required) | RDS allocated storage, GB |
| `backup_retention_period` | — (required) | Days to retain automated RDS backups |
| `multi_az` | — (required) | RDS Multi-AZ — roughly doubles cost when `true` |
| `cloudwatch_namespace` | — (required) | Namespace for the CloudWatch Observability addon |
| `eks_public_access_cidrs` | `["0.0.0.0/0"]` | CIDRs allowed to reach the EKS public API endpoint |

### Platform submodule (ALB controller, Cluster Autoscaler, ESO, Redis, Neo4j, ArgoCD, KEDA, Reloader)

| Variable | Default | What it controls |
|---|---|---|
| `argocd_namespace` | `"argocd"` | ArgoCD's namespace |
| `argocd_admin_password_hashed` | `""` | Bcrypt hash; ignored for self-service (generated directly instead) |
| `eso_chart_version` | `"0.10.3"` | External Secrets Operator chart version |
| `keda_chart_version` | `"2.16.0"` | KEDA chart version |
| `reloader_chart_version` | `"1.2.0"` | Stakater Reloader chart version — restarts pods when K8s Secrets change |
| `alb_controller_chart_version` | `"1.12.0"` | AWS Load Balancer Controller chart version |
| `cluster_autoscaler_chart_version` | `"9.59.0"` | Cluster Autoscaler chart version |
| `enable_redis` | `false` | Deploy in-cluster Redis (Bitnami Redis Stack) — the app's ERD/KEDA features need it |
| `redis_namespace` | `"redis"` | Redis namespace |
| `redis_chart_version` | `"20.6.2"` | Bitnami Redis chart version |
| `redis_replica_count` | `1` | Redis read-replica pod count |
| `redis_persistence_size` | `"8Gi"` | PVC size per Redis pod |
| `redis_storage_class` | `"gp2"` | StorageClass for Redis PVCs (`gp3` for prod) |
| `redis_metrics_enabled` | `false` | Deploy the redis-exporter sidecar — off by default, nothing scrapes it |
| `redis_network_policy_enabled` | `true` | Restrict Redis traffic to in-cluster pods |
| `enable_neo4j` | `false` | Deploy in-cluster Neo4j (community edition) — the app's ERD features need it |
| `neo4j_namespace` | `"neo4j"` | Neo4j namespace |
| `neo4j_chart_version` | `"5.26.0"` | Neo4j chart version |
| `neo4j_storage_size` | `"20Gi"` | PVC size for Neo4j's data volume |
| `neo4j_storage_class` | `"gp3"` | StorageClass for the Neo4j PVC |
| `neo4j_memory_request` / `neo4j_memory_limit` | `"2Gi"` / `"4Gi"` | Neo4j pod memory sizing |
| `neo4j_cpu_request` / `neo4j_cpu_limit` | `"500m"` / `"2"` | Neo4j pod CPU sizing |

### `cicd/variables.tf` — self-service app config

| Variable | Default | What it controls |
|---|---|---|
| `shared_service_account_name` | `"ekai-app-sa"` | ServiceAccount every service runs as — must match the `ekai-saas` chart's `serviceAccountName` |
| `image_tag` | `""` | Image tag deployed — passed through as the chart's `imageTag` |
| `erd_storage_class` | `"gp3"` | StorageClass for ERD's workspace PVC |
| `ingress_class_name` | `"alb"` | Ingress controller class — only `"alb"` wires `shared_alb_name`/cert/subnets automatically |
| `shared_alb_name` | `""` → `"ekai<env>-shared-alb"` | Name of the shared ALB the chart's Ingress creates |
| `use_minio` | `false` | Use a MinIO/S3-compatible endpoint instead of real S3 — Terraform doesn't deploy MinIO either way, only makes sense if you run your own |
| `claude_model` | `"claude-haiku-4-5-20251001"` | Claude model the semantics service uses |
| `vector_embedding_model` | `"text-embedding-3-small"` | OpenAI embedding model for vector search |
| `vector_embedding_batch_size` | `100` | Batch size for embedding generation |
| `secret_recovery_window_days` | `0` | Recovery window before the app secret is permanently deleted after `terraform destroy` — `0` lets an immediate re-apply reuse the same name |
| `secret_value_overrides` | `{}` | Map to override any individual key in the generated app secret |
| `manifest_folder` | `"manifest-files"` | Folder in the `deployment-files` repo where K8s manifests live |
| `helm_chart_repo_url` | `""` | OCI registry the `ekai-saas` chart is published to — bare host+path, no `oci://` prefix |
| `helm_chart_version` | `"*"` | Chart version — `"*"` auto-tracks latest via ArgoCD, no apply needed per release |
| `ekai_namespace` | — (required) | Kubernetes namespace for the app's services |
| `existing_ecr_base_url` | `null` | Where container images are pulled from — also the chart's `imageRegistry` |

### `cicd/variables.tf` — not functional in this distribution

Declared (so `cicd_provider` still validates) but inert — their supporting
modules (`code_build`, `github_actions_cicd`, `amplify_frontend`) aren't
included here: `pipelines`, `CD_branch`, `github_org`, `ekai_web_branch`,
`ekai_web_ingresshost`, `ekai_web_env`, `create_github_oidc_provider`,
`create_ecr`.
