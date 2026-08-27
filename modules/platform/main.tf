# ──────────────────────────────────────────────────────────────────────────────
# Layer 03 — Platform (Helm releases + cluster-level infrastructure)
# Depends on the cluster submodule. Provisions everything that runs INSIDE EKS.
# ──────────────────────────────────────────────────────────────────────────────

check "argocd_password_provided_when_not_self_service" {
  assert {
    condition     = var.cicd_provider == "none" || var.argocd_admin_password_hashed != ""
    error_message = "argocd_admin_password_hashed must be set when cicd_provider != \"none\" (self-service generates it directly instead)."
  }
}

locals {
  oidc_issuer         = var.oidc_issuer
  oidc_provider_arn   = var.oidc_provider_arn
  public_subnet_ids   = var.public_subnet_ids
  vpc_id              = var.vpc_id
  ssl_certificate_arn = var.ssl_certificate_arn
  route53_zone_id     = var.route53_zone_id
  eks_cluster_name    = var.eks_cluster_name
  argocd_host         = coalesce(var.argocd_ingress_host, "argocd.${var.dns_zone}")
  self_service        = var.cicd_provider == "none"

  # self_service only — no master secret to read a hashed admin password
  # from, generate it directly instead. Read from terraform_data below, not
  # bcrypt() directly -- bcrypt() generates a fresh random salt on every
  # single call, so a plain local would produce a DIFFERENT hash on every
  # plan/apply even though the underlying password never changes, making
  # ArgoCD's admin secret look "modified" forever.
  argocd_admin_password_hashed = local.self_service ? terraform_data.argocd_admin_password_hashed[0].output : var.argocd_admin_password_hashed
}

resource "random_password" "argocd_admin" {
  count   = local.self_service ? 1 : 0
  length  = 24
  special = false
}

resource "terraform_data" "argocd_admin_password_hashed" {
  count = local.self_service ? 1 : 0
  input = bcrypt(random_password.argocd_admin[0].result, 10)

  lifecycle {
    ignore_changes = [input]
  }
}

# ── ALB Controller (IRSA + Helm) ──────────────────────────────────────────────
# OIDC provider was created in 02-cluster; alb_controller/iam.tf derives the ARN
# from the issuer URL, so we pass the issuer URL in both fields.
#
module "alb_controller" {
  source                           = "../alb_controller"
  cluster_name                     = local.eks_cluster_name
  cluster_identity_oidc_issuer     = local.oidc_issuer
  cluster_identity_oidc_issuer_arn = local.oidc_issuer
  aws_region                       = var.region
  helm_chart_version               = var.alb_controller_chart_version
  settings = {
    vpcId = local.vpc_id
  }
}

# ── Cluster Autoscaler (IRSA + Helm) ──────────────────────────────────────────
# Scales the node group's ASG within the min/max already set in 02-cluster's
# scaling_config (node_min_size/mode_max_size) — no cluster-level change
# needed to raise the ceiling, just edit mode_max_size in tfvars.
module "cluster_autoscaler" {
  source                           = "../cluster_autoscaler"
  cluster_name                     = local.eks_cluster_name
  cluster_identity_oidc_issuer     = local.oidc_issuer
  cluster_identity_oidc_issuer_arn = local.oidc_issuer
  aws_region                       = var.region
  node_group_asg_name              = var.node_group_asg_name
  helm_chart_version               = var.cluster_autoscaler_chart_version
}

# On destroy: argoCD + keda depend on this time_sleep, so they are destroyed
# first. time_sleep then waits 2 minutes (destroy_duration) giving the ALB
# Controller time to reconcile Ingress deletions and delete the ALBs from AWS
# before alb_controller itself is destroyed and its IRSA role removed.
# On apply: create_duration = 0s so there is no delay.
resource "time_sleep" "wait_for_alb_cleanup" {
  create_duration  = "0s"
  destroy_duration = "2m"
  depends_on       = [module.alb_controller]
}

# ── External Secrets Operator (IRSA + Helm + ClusterSecretStore) ──────────────
# Mirrors Azure's modules/external_secrets — reads from Secrets Manager,
# creates K8s Secrets in any namespace on demand via ExternalSecret CRDs.
module "eso" {
  source               = "../eso"
  env                  = var.env
  region               = var.region
  oidc_issuer_url      = local.oidc_issuer
  chart_version        = var.eso_chart_version
  customer_secret_name = local.self_service ? var.customer_secret_name : ""
  depends_on           = [time_sleep.wait_for_alb_cleanup]
}

# ── Redis (optional — Bitnami Redis Stack, in-cluster) ────────────────────────
# Set enable_redis = true in env/*.tfvars to deploy. When enabled, 04-cicd
# automatically merges REDIS_HOST/PORT/PASSWORD/URL into per-service app secrets
# so pods receive them via ESO without any manual secret management.
module "redis" {
  count  = var.enable_redis ? 1 : 0
  source = "../redis"

  redis_namespace        = var.redis_namespace
  chart_version          = var.redis_chart_version
  replica_count          = var.redis_replica_count
  persistence_size       = var.redis_persistence_size
  storage_class          = var.redis_storage_class
  metrics_enabled        = var.redis_metrics_enabled
  network_policy_enabled = var.redis_network_policy_enabled

  depends_on = [time_sleep.wait_for_alb_cleanup, module.eso]
}

# ── Neo4j (optional — Neo4j Helm chart, community edition, in-cluster) ───────
# Set enable_neo4j = true in env/*.tfvars to deploy. Client adds NEO4J_URI/
# NEO4J_USERNAME/NEO4J_PASSWORD to their own per-service secret manually (same
# manual-secret convention documented for Redis/DB creds in the README) —
# this layer does not merge them automatically.
module "neo4j" {
  count  = var.enable_neo4j ? 1 : 0
  source = "../neo4j"

  namespace      = var.neo4j_namespace
  chart_version  = var.neo4j_chart_version
  storage_size   = var.neo4j_storage_size
  storage_class  = var.neo4j_storage_class
  memory_request = var.neo4j_memory_request
  memory_limit   = var.neo4j_memory_limit
  cpu_request    = var.neo4j_cpu_request
  cpu_limit      = var.neo4j_cpu_limit

  depends_on = [time_sleep.wait_for_alb_cleanup, module.eso]
}

# ── Reloader — auto-restart pods when K8s Secrets change ─────────────────────
# Watches K8s Secrets/ConfigMaps and triggers rolling restarts on any pod
# that has the annotation: reloader.stakater.com/auto: "true"
# Required: ESO updates the K8s Secret but pods need a restart to pick up
# the new env vars. Reloader automates this without manual intervention.
resource "helm_release" "reloader" {
  name             = "reloader"
  repository       = "https://stakater.github.io/stakater-charts"
  chart            = "reloader"
  version          = var.reloader_chart_version
  namespace        = "kube-system"
  create_namespace = false
  timeout          = 300
  cleanup_on_fail  = true

  set {
    name  = "reloader.watchGlobally"
    value = "true"
  }

  depends_on = [time_sleep.wait_for_alb_cleanup]
}

# ── KEDA (event-driven autoscaler) ───────────────────────────────────────────
# Always deployed — used to scale ekai-erd-worker based on Redis queue length.
# Runs independently of enable_redis; KEDA ScaledObjects in deployment-files
# are simply inactive until Redis is available.
resource "kubernetes_namespace" "keda" {
  metadata {
    name = "keda"
  }
  depends_on = [time_sleep.wait_for_alb_cleanup]
}

resource "helm_release" "keda" {
  name             = "keda"
  repository       = "https://kedacore.github.io/charts"
  chart            = "keda"
  version          = var.keda_chart_version
  namespace        = kubernetes_namespace.keda.metadata[0].name
  create_namespace = false
  timeout          = 600
  cleanup_on_fail  = true

  depends_on = [kubernetes_namespace.keda]
}

# ── ArgoCD (Helm + Route53 + DNS wait) ────────────────────────────────────────
module "argoCD" {
  source                       = "../argoCD"
  argocd_namespace             = var.argocd_namespace
  argocd_admin_password_hashed = local.argocd_admin_password_hashed
  argocd_ingress_host          = local.argocd_host
  route53_zone_id              = local.route53_zone_id
  ssl_certificate_arn          = local.ssl_certificate_arn
  pub_subnet_ids               = local.public_subnet_ids
  env                          = var.env
  depends_on                   = [time_sleep.wait_for_alb_cleanup, module.eso]
}
