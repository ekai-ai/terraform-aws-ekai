# ──────────────────────────────────────────────────────────────────────────────
# cicd — separate apply/state from the combined bootstrap+cluster+platform
# root one directory up (see ../main.tf's file header for the full reasoning).
# In short: the argocd Terraform provider's `password` field must be a value
# Terraform already knows before apply — it cannot be a same-apply managed
# resource attribute the way kubernetes/helm/kubectl's `exec`-block auth can.
# module.platform's freshly-generated ArgoCD admin password is exactly such
# an attribute, so this apply has to run separately, AFTER the combined one
# has already finished and written that password to state.
#
# Reads the combined root's own state via terraform_remote_state — same
# mechanism the original 04-cicd/main.tf used to read 03-platform's (and
# 02-cluster's, and 01-bootstrap's) state, just pointed at the new combined
# state instead of 3 separate ones.
# ──────────────────────────────────────────────────────────────────────────────

data "terraform_remote_state" "combined" {
  backend = "s3"
  config = {
    bucket  = "ekai-terraform-state-${var.env}-${var.region}"
    key     = "${var.env}/combined.tfstate"
    region  = var.region
    encrypt = true
  }
}

module "cicd" {
  source = "../modules/cicd"

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

  # formerly `data "terraform_remote_state" "cluster"` in the original
  # 04-cicd/main.tf — now reads the combined root's state instead
  aws_account_id        = data.terraform_remote_state.combined.outputs.aws_account_id
  backend_db_username   = data.terraform_remote_state.combined.outputs.backend_db_username
  backend_db_password   = data.terraform_remote_state.combined.outputs.backend_db_password
  backend_db_name       = data.terraform_remote_state.combined.outputs.backend_db_name
  semantics_db_username = data.terraform_remote_state.combined.outputs.semantics_db_username
  semantics_db_password = data.terraform_remote_state.combined.outputs.semantics_db_password
  semantics_db_name     = data.terraform_remote_state.combined.outputs.semantics_db_name
  rds_endpoint          = data.terraform_remote_state.combined.outputs.rds_endpoint
  public_subnet_ids     = data.terraform_remote_state.combined.outputs.public_subnet_ids
  vpc_id                = data.terraform_remote_state.combined.outputs.vpc_id
  private_subnet_ids    = data.terraform_remote_state.combined.outputs.private_subnet_ids
  rds_sg_id             = data.terraform_remote_state.combined.outputs.rds_sg_id
  oidc_issuer           = data.terraform_remote_state.combined.outputs.oidc_issuer

  # formerly `data "terraform_remote_state" "platform"` in the original
  # 04-cicd/main.tf
  argocd_admin_password_plaintext = data.terraform_remote_state.combined.outputs.argocd_admin_password_plaintext
  redis_credentials               = data.terraform_remote_state.combined.outputs.redis_credentials
  neo4j_credentials               = data.terraform_remote_state.combined.outputs.neo4j_credentials
  cluster_secret_store_name       = data.terraform_remote_state.combined.outputs.cluster_secret_store_name

  # formerly `data "terraform_remote_state" "bootstrap"` in the original
  # 04-cicd/main.tf
  ssl_certificate_arn = data.terraform_remote_state.combined.outputs.ssl_certificate_arn
  route53_zone_id     = data.terraform_remote_state.combined.outputs.route53_zone_id
}
