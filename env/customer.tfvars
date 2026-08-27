# Self-service client template — "customer" stands in for a real customer
# name. Unlike dev/qa/staging/prod (Ekai's own environments), a self-service
# deployment isn't a tier — it's one client's own AWS account. Copy this
# file, rename it to the client's actual name, fill in the values below.
#
# This repo is 2 separate Terraform root configs — this ONE tfvars file
# feeds both (exactly like the original 4-layer design, where one tfvars
# file already served all 4 layers; each config simply ignores the tfvars
# keys it doesn't declare a variable for):
#   .  (repo root) — bootstrap + cluster + platform, combined into one apply/
#      state (down from 3 separate ones in the original design)
#   cicd/           — kept as its own separate apply/state, same as the
#      original 04-cicd layer, because the ArgoCD Terraform provider can only
#      be configured from a value read from an ALREADY-COMPLETED apply's
#      state (a remote_state read), never from a resource this SAME apply
#      also creates — see cicd/main.tf's file header for the full reasoning.
#
# So: 2 backend config files, 2 inits, 2 applies (in order — cicd depends on
# the root's state). Run scripts/init-state-backend.sh <name> to generate
# both, then:
#   terraform init -backend-config=env/backend-<name>.tfbackend
#   terraform apply -var-file=env/<name>.tfvars
#   cd cicd
#   terraform init -backend-config=../env/backend-<name>-cicd.tfbackend
#   terraform apply -var-file=../env/<name>.tfvars
# (scripts/self-deploy.sh does all of this for you, in order.)
#
# route53_zone_id and ssl_certificate_arn are NOT set here even though the
# bootstrap/platform/cicd submodules use both internally — they're generated
# by the bootstrap submodule and wired automatically (via module outputs at
# root, via a remote_state read in cicd/). There's nothing for a human to set
# for them.

region           = "us-east-1"
env              = "customer"
eks_cluster_name = "ekai-eks"

vpc_cidr             = "172.16.0.0/20"
public_subnet_cidrs  = ["172.16.4.0/26", "172.16.8.0/26"]
private_subnet_cidrs = ["172.16.12.0/26", "172.16.14.0/26", "172.16.15.0/26"]
# cluster_version = "1.32"   # uncomment to pin a specific version, otherwise AWS uses latest

node_min_size           = "3"
mode_max_size           = "5"
node_instance           = "c5.xlarge"
allocated_storage       = "40"
backup_retention_period = "7"
db_instance_class       = "db.t3.medium"
multi_az                = "true"
cloudwatch_namespace    = "amazon-cloudwatch"
# Check `aws rds describe-db-engine-versions --engine postgres` if this 400s
# on apply — AWS periodically drops old minor versions from the supported list.
engine_version   = "15.19"
rds_storage_type = "gp2"

# ─── bootstrap submodule (Route53 zone + ACM certificate) ────────────────────
# manage_dns_zone = true  → Terraform creates the Route53 zone below.
# A real client with their own domain already in Route53 would instead set
# manage_dns_zone = false and provide route53_zone_id.
dns_zone        = "customer.ekai.ai" # stand-in — a real client uses their own domain
manage_dns_zone = true

# ─── platform submodule ────────────────────────────────────────────────────────
argocd_namespace = "argocd"
# argocd_admin_password_hashed intentionally omitted — cicd_provider = "none"
# generates its own ArgoCD admin password + hash directly (platform submodule).

# In-cluster Redis + Neo4j — the ekai-saas chart's ERD/KEDA needs both.
enable_redis = true
enable_neo4j = true

# ─── cicd/ (separate apply) — self-service mode ────────────────────────────────
# cicd_provider = "none" is the entire point of this file: no CodeBuild, no
# GitHub Actions, no Amplify — ArgoCD pulls the ekai-saas Helm chart
# directly. None of pipelines/CD_branch/github_org/ekai_web_* apply here.
cicd_provider = "none"

ekai_namespace = "ekai-saas"

# Real, public, no-login images this session pushed to public.ecr.aws —
# a real client would point this at wherever Ekai publishes release images.
existing_ecr_base_url = "public.ecr.aws/s7m9t1b0"
image_tag             = "latest"

# Chart Terraform installs via ArgoCD — "*" tracks latest automatically.
# OCI registry (public.ecr.aws), not the deployment-files repo's GitHub
# Pages: that repo is private, and GitHub only serves private-repo Pages
# through an authenticated-only URL — unreachable by ArgoCD running with no
# GitHub credentials in a customer's own cluster.
helm_chart_repo_url = "public.ecr.aws/s7m9t1b0/ekai-helm"
helm_chart_version  = "*"

# customer_secret_name defaults to "ekai-customer" — left as default.
# shared_service_account_name defaults to "ekai-app-sa" — left as default.
# erd_storage_class defaults to "gp3" — left as default.
