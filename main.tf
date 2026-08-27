# ──────────────────────────────────────────────────────────────────────────────
# Root module — composes 3 of the 4 submodules (bootstrap, cluster, platform)
# that used to be 4 separate root modules chained via `terraform_remote_state`,
# each with its own S3 backend/state. Now: one apply, one state for these 3;
# module outputs wire submodule-to-submodule directly instead of remote-state
# reads.
#
# The 4th submodule (cicd) is deliberately NOT included here — it stays a
# separate apply/state at ../cicd/, reading THIS config's outputs via
# `data "terraform_remote_state"` (see ../cicd/main.tf). Why: this root's
# provider "kubernetes"/"helm"/"kubectl" blocks below can safely be configured
# from module.cluster's own same-apply outputs (cluster_endpoint/cluster_ca)
# because their `exec` block defers actual authentication until first use —
# a deliberately-supported escape hatch, and the same pattern the source
# codebase's own 02-cluster layer already relied on. The ArgoCD Terraform
# provider (argoproj-labs/argocd) has no equivalent mechanism: its `password`
# field is read eagerly, so it can only be set from a value Terraform already
# knows before apply — i.e. a remote_state read against an already-completed
# apply, never a same-apply managed-resource attribute (module.platform's
# freshly-generated argocd_admin_password_plaintext). That's the one boundary
# where the "single combined apply" simplification genuinely does not work,
# so it stays split here, mirroring the original 4-layer design for exactly
# this one seam.
#
# Apply order matches the original layer order (01 → 02 → 03); depends_on on
# each module block enforces it explicitly since Terraform can't always infer
# full ordering from the module.X.Y references alone (some resources inside a
# submodule, e.g. the kubernetes/helm/kubectl-backed ones, don't reference
# upstream outputs directly — they rely on the *provider* configuration at
# root already pointing at a live cluster).
# ──────────────────────────────────────────────────────────────────────────────

module "bootstrap" {
  source = "./modules/bootstrap"

  region               = var.region
  env                  = var.env
  dns_zone             = var.dns_zone
  manage_dns_zone      = var.manage_dns_zone
  route53_zone_id      = var.route53_zone_id
  vpc_cidr             = var.vpc_cidr
  public_subnet_cidrs  = var.public_subnet_cidrs
  private_subnet_cidrs = var.private_subnet_cidrs
  eks_cluster_name     = var.eks_cluster_name
}

module "cluster" {
  source     = "./modules/cluster"
  depends_on = [module.bootstrap]

  region                  = var.region
  env                     = var.env
  eks_cluster_name        = var.eks_cluster_name
  cluster_version         = var.cluster_version
  node_min_size           = var.node_min_size
  mode_max_size           = var.mode_max_size
  node_instance           = var.node_instance
  node_ami_type           = var.node_ami_type
  node_disk_size          = var.node_disk_size
  db_instance_class       = var.db_instance_class
  engine_version          = var.engine_version
  rds_storage_type        = var.rds_storage_type
  allocated_storage       = var.allocated_storage
  backup_retention_period = var.backup_retention_period
  multi_az                = var.multi_az
  cloudwatch_namespace    = var.cloudwatch_namespace
  secrets_name            = var.secrets_name
  cicd_provider           = var.cicd_provider
  eks_public_access_cidrs = var.eks_public_access_cidrs

  # formerly `data "terraform_remote_state" "bootstrap"` in 02-cluster/main.tf
  vpc_id             = module.bootstrap.vpc_id
  vpc_cidr           = module.bootstrap.vpc_cidr
  private_subnet_ids = module.bootstrap.private_subnet_ids
  public_subnet_ids  = module.bootstrap.public_subnet_ids
}

module "platform" {
  source     = "./modules/platform"
  depends_on = [module.cluster]

  region                       = var.region
  env                          = var.env
  argocd_namespace             = var.argocd_namespace
  argocd_admin_password_hashed = var.argocd_admin_password_hashed
  cicd_provider                = var.cicd_provider
  customer_secret_name         = var.customer_secret_name
  argocd_ingress_host          = var.argocd_ingress_host
  dns_zone                     = var.dns_zone
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

  # formerly `data "terraform_remote_state" "cluster"` / "bootstrap" in 03-platform/main.tf
  oidc_issuer         = module.cluster.oidc_issuer
  oidc_provider_arn   = module.cluster.oidc_provider_arn
  public_subnet_ids   = module.cluster.public_subnet_ids
  vpc_id              = module.cluster.vpc_id
  eks_cluster_name    = module.cluster.eks_cluster_name
  node_group_asg_name = module.cluster.node_group_asg_name
  ssl_certificate_arn = module.bootstrap.ssl_certificate_arn
  route53_zone_id     = module.bootstrap.route53_zone_id
}
