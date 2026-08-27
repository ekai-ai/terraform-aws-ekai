# ──────────────────────────────────────────────────────────────────────────────
# examples/self-deploy/cicd — the actual state-holding root config for the
# "cicd" module (../../../cicd = the repo's cicd/ directory). This is what
# scripts/self-deploy.sh runs `terraform init`/`apply` against, AFTER
# examples/self-deploy/root has already applied — cicd/'s own
# `data "terraform_remote_state" "combined"` block (inside ../../../cicd/
# main.tf) reads that apply's state directly, so this config doesn't need to
# pass any remote-state values itself; the module block below only carries
# genuine tfvars-driven inputs.
#
# required_providers here matches ../../../cicd/providers.tf's exactly — see
# examples/self-deploy/root/main.tf's header comment for why re-declaring
# matters even though the cicd module already configures these providers
# internally.
# ──────────────────────────────────────────────────────────────────────────────

terraform {
  required_version = ">= 1.5"

  # Partial backend config — provide per-environment via -backend-config flag.
  # Example:
  #   terraform init -backend-config=../../../env/backend-<env>-cicd.tfbackend
  #
  # Second of the 2 states in this repo — see scripts/init-state-backend.sh
  # (run from the repo root — it writes backend files into env/, not here).
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
    kubectl = {
      source  = "gavinbunney/kubectl"
      version = "~> 1.14"
    }
    argocd = {
      source  = "argoproj-labs/argocd"
      version = "~> 7.11"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
    time = {
      source  = "hashicorp/time"
      version = "~> 0.12"
    }
    null = {
      source  = "hashicorp/null"
      version = "~> 3.2"
    }
  }
}

module "cicd" {
  source = "../../../cicd"

  region                      = var.region
  env                         = var.env
  argocd_ingress_host         = var.argocd_ingress_host
  dns_zone                    = var.dns_zone
  secrets_name                = var.secrets_name
  customer_secret_name        = var.customer_secret_name
  shared_service_account_name = var.shared_service_account_name
  image_tag                   = var.image_tag
  erd_storage_class           = var.erd_storage_class
  ingress_class_name          = var.ingress_class_name
  shared_alb_name             = var.shared_alb_name
  use_minio                   = var.use_minio
  claude_model                = var.claude_model
  vector_embedding_model      = var.vector_embedding_model
  vector_embedding_batch_size = var.vector_embedding_batch_size
  secret_recovery_window_days = var.secret_recovery_window_days
  secret_value_overrides      = var.secret_value_overrides
  manifest_folder             = var.manifest_folder
  cicd_provider               = var.cicd_provider
  helm_chart_repo_url         = var.helm_chart_repo_url
  helm_chart_version          = var.helm_chart_version
  pipelines                   = var.pipelines
  CD_branch                   = var.CD_branch
  github_org                  = var.github_org
  ekai_namespace              = var.ekai_namespace
  ekai_web_branch             = var.ekai_web_branch
  ekai_web_ingresshost        = var.ekai_web_ingresshost
  ekai_web_env                = var.ekai_web_env
  create_github_oidc_provider = var.create_github_oidc_provider
  create_ecr                  = var.create_ecr
  existing_ecr_base_url       = var.existing_ecr_base_url
}
