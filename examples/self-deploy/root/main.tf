# ──────────────────────────────────────────────────────────────────────────────
# examples/self-deploy/root — the actual state-holding root config for the
# "infra" module (../../.. = the repo root — bootstrap+cluster+platform,
# combined into one apply). This is what scripts/self-deploy.sh runs
# `terraform init`/`apply` against; the repo root itself is a pure module now
# (no backend block — see ../../../providers.tf) and cannot be applied
# directly.
#
# required_providers here matches ../../../providers.tf's exactly — the repo
# root module already declares (and configures) these providers internally,
# but re-declaring the same versions at the true root pins them at the entry
# point too, which is what actually determines what `terraform init`
# installs and locks in .terraform.lock.hcl.
# ──────────────────────────────────────────────────────────────────────────────

terraform {
  required_version = ">= 1.9"

  # Partial backend config — provide per-environment via -backend-config flag.
  # Example:
  #   terraform init -backend-config=../../../env/backend-<env>.tfbackend
  #
  # The S3 state bucket MUST exist before terraform init can succeed.
  # Create it first with: scripts/init-state-backend.sh <env> (from the repo
  # root — it writes backend files into env/, not here).
  #
  # This is one of TWO separate states in this repo — this one holds
  # bootstrap+cluster+platform ("combined"); examples/self-deploy/cicd/ holds
  # its own, reading this state's outputs via `data "terraform_remote_state"`
  # (inside the cicd module itself). See scripts/init-state-backend.sh for
  # the exact key each gets.
  backend "s3" {}

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.38"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.38"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.16"
    }
    kubectl = {
      source  = "gavinbunney/kubectl"
      version = "~> 1.14"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
    time = {
      source  = "hashicorp/time"
      version = "~> 0.12"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }
}

module "infra" {
  source = "../../.."

  region                       = var.region
  env                          = var.env
  dns_zone                     = var.dns_zone
  eks_cluster_name             = var.eks_cluster_name
  secrets_name                 = var.secrets_name
  customer_secret_name         = var.customer_secret_name
  argocd_ingress_host          = var.argocd_ingress_host
  cicd_provider                = var.cicd_provider
  manage_dns_zone              = var.manage_dns_zone
  route53_zone_id              = var.route53_zone_id
  vpc_cidr                     = var.vpc_cidr
  public_subnet_cidrs          = var.public_subnet_cidrs
  private_subnet_cidrs         = var.private_subnet_cidrs
  cluster_version              = var.cluster_version
  node_min_size                = var.node_min_size
  mode_max_size                = var.mode_max_size
  node_instance                = var.node_instance
  node_ami_type                = var.node_ami_type
  node_disk_size               = var.node_disk_size
  db_instance_class            = var.db_instance_class
  engine_version               = var.engine_version
  rds_storage_type             = var.rds_storage_type
  allocated_storage            = var.allocated_storage
  backup_retention_period      = var.backup_retention_period
  multi_az                     = var.multi_az
  cloudwatch_namespace         = var.cloudwatch_namespace
  eks_public_access_cidrs      = var.eks_public_access_cidrs
  argocd_namespace             = var.argocd_namespace
  argocd_admin_password_hashed = var.argocd_admin_password_hashed
  eso_chart_version            = var.eso_chart_version
  keda_chart_version           = var.keda_chart_version
  reloader_chart_version       = var.reloader_chart_version
  alb_controller_chart_version = var.alb_controller_chart_version
  enable_redis                 = var.enable_redis
  redis_namespace              = var.redis_namespace
  redis_chart_version          = var.redis_chart_version
  redis_replica_count          = var.redis_replica_count
  redis_persistence_size       = var.redis_persistence_size
  redis_storage_class          = var.redis_storage_class
  redis_metrics_enabled        = var.redis_metrics_enabled
  redis_network_policy_enabled = var.redis_network_policy_enabled
  enable_neo4j                 = var.enable_neo4j
  neo4j_namespace              = var.neo4j_namespace
  neo4j_chart_version          = var.neo4j_chart_version
  neo4j_storage_size           = var.neo4j_storage_size
  neo4j_storage_class          = var.neo4j_storage_class
  neo4j_memory_request         = var.neo4j_memory_request
  neo4j_memory_limit           = var.neo4j_memory_limit
  neo4j_cpu_request            = var.neo4j_cpu_request
  neo4j_cpu_limit              = var.neo4j_cpu_limit
}
