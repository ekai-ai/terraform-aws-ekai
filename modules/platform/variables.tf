variable "region" {
  description = "AWS region"
  type        = string
}

variable "env" {
  description = "Environment name (e.g., dev, test, prod)"
  type        = string
}

variable "argocd_namespace" {
  description = "Kubernetes namespace for ArgoCD"
  type        = string
  default     = "argocd"
}

variable "argocd_admin_password_hashed" {
  description = "Bcrypt-hashed ArgoCD admin password. Ignored when cicd_provider = \"none\" — generated directly instead."
  type        = string
  sensitive   = true
  default     = ""
}

variable "cicd_provider" {
  description = <<-EOT
    Same value as the cicd submodule's cicd_provider (the root module's single
    tfvars file is shared across all 4 submodules) — only checked here for
    whether it's "none" (self-service: generate the ArgoCD admin password
    directly instead of requiring argocd_admin_password_hashed + a master
    secret with its plaintext counterpart). Which of "codebuild"/
    "github_actions" otherwise makes no difference to this layer.
  EOT
  type        = string
  default     = "none"
  validation {
    condition     = contains(["codebuild", "github_actions", "none"], var.cicd_provider)
    error_message = "cicd_provider must be 'codebuild', 'github_actions', or 'none'."
  }
}

variable "customer_secret_name" {
  description = <<-EOT
    Same value as the cicd submodule's customer_secret_name (the root
    module's single tfvars file is shared across all 4 submodules) — only
    used here (cicd_provider = "none") to also scope the ESO IRSA role's
    Secrets Manager read access to this secret. It doesn't follow the
    "<env>-*" naming convention every other secret in this codebase uses, so
    modules/eso's policy needs it explicitly. Ignored otherwise.
  EOT
  type        = string
  default     = "ekai-customer"
}

variable "argocd_ingress_host" {
  description = "Hostname for the ArgoCD ingress. Optional — defaults to \"argocd.<dns_zone>\" when omitted."
  type        = string
  default     = null
}

variable "dns_zone" {
  description = "Base DNS zone for this environment (e.g. dev-eks.ekai.ai). Used to derive argocd_ingress_host when not explicitly set."
  type        = string
}

variable "eso_chart_version" {
  description = "ESO Helm chart version"
  type        = string
  default     = "0.10.3"
}

variable "keda_chart_version" {
  description = "KEDA Helm chart version"
  type        = string
  default     = "2.16.0"
}

variable "reloader_chart_version" {
  description = "Stakater Reloader Helm chart version — auto-restarts pods when K8s Secrets change"
  type        = string
  default     = "1.2.0"
}

# ── Redis (optional) ──────────────────────────────────────────────────────────

variable "enable_redis" {
  description = "Deploy in-cluster Redis (Bitnami Redis Stack). Set true to enable; false skips all Redis resources."
  type        = bool
  default     = false
}

variable "redis_namespace" {
  description = "Kubernetes namespace for Redis."
  type        = string
  default     = "redis"
}

variable "alb_controller_chart_version" {
  description = "AWS Load Balancer Controller Helm chart version."
  type        = string
  default     = "1.12.0"
}

variable "cluster_autoscaler_chart_version" {
  description = "Cluster Autoscaler Helm chart version."
  type        = string
  default     = "9.59.0"
}

variable "redis_chart_version" {
  description = "Bitnami Redis Helm chart version."
  type        = string
  default     = "20.6.2"
}

variable "redis_replica_count" {
  description = "Number of Redis read-replica pods (0 for dev, 1+ for prod)."
  type        = number
  default     = 1
}

variable "redis_persistence_size" {
  description = "PVC size for each Redis pod."
  type        = string
  default     = "8Gi"
}

variable "redis_storage_class" {
  description = "StorageClass for Redis PVCs. AWS default is gp2; use gp3 for prod."
  type        = string
  default     = "gp2"
}

variable "redis_metrics_enabled" {
  description = "Deploy the redis-exporter sidecar for Prometheus scraping. Default false: nothing in this stack scrapes it, and Bitnami has been pruning old free-tier image tags (see modules/redis/variables.tf)."
  type        = bool
  default     = false
}

variable "redis_network_policy_enabled" {
  description = "Apply a NetworkPolicy restricting Redis traffic to in-cluster pods."
  type        = bool
  default     = true
}

# ── Neo4j (optional) ────────────────────────────────────────────────────────

variable "enable_neo4j" {
  description = "Deploy in-cluster Neo4j (community edition). Set true to enable; false skips all Neo4j resources."
  type        = bool
  default     = false
}

variable "neo4j_namespace" {
  description = "Kubernetes namespace for Neo4j."
  type        = string
  default     = "neo4j"
}

variable "neo4j_chart_version" {
  description = "Neo4j Helm chart version."
  type        = string
  default     = "5.26.0"
}

variable "neo4j_storage_size" {
  description = "PVC size for Neo4j's data volume."
  type        = string
  default     = "20Gi"
}

variable "neo4j_storage_class" {
  description = "StorageClass for the Neo4j PVC (provisioned by the EBS CSI driver addon in 02-cluster)."
  type        = string
  default     = "gp3"
}

variable "neo4j_memory_request" {
  type    = string
  default = "2Gi"
}

variable "neo4j_memory_limit" {
  type    = string
  default = "4Gi"
}

variable "neo4j_cpu_request" {
  type    = string
  default = "500m"
}

variable "neo4j_cpu_limit" {
  type    = string
  default = "2"
}

# ── Formerly read via `data "terraform_remote_state" "cluster"` / "bootstrap" ─
# Wired automatically from module.cluster's / module.bootstrap's outputs by
# the root module (see ../../main.tf) — nothing to set in tfvars for these.

variable "oidc_issuer" {
  description = "OIDC issuer URL of the EKS cluster (sourced from the cluster submodule's output)"
  type        = string
}

variable "oidc_provider_arn" {
  description = "ARN of the IAM OIDC provider (sourced from the cluster submodule's output)"
  type        = string
}

variable "public_subnet_ids" {
  description = "Public subnet IDs (sourced from the cluster submodule's output)"
  type        = list(string)
}

variable "vpc_id" {
  description = "VPC ID (sourced from the cluster submodule's output)"
  type        = string
}

variable "eks_cluster_name" {
  description = "Full EKS cluster name (sourced from the cluster submodule's output)"
  type        = string
}

variable "node_group_asg_name" {
  description = "Name of the node group's Auto Scaling Group (sourced from the cluster submodule's output) — Cluster Autoscaler auto-discovers and scales this"
  type        = string
}

variable "route53_zone_id" {
  description = "Route53 hosted zone ID. Sourced automatically from the bootstrap submodule's output — nothing to set in tfvars."
  type        = string
}

variable "ssl_certificate_arn" {
  description = "ACM certificate ARN. Sourced automatically from the bootstrap submodule's output — nothing to set in tfvars."
  type        = string
}
