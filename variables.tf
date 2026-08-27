# ──────────────────────────────────────────────────────────────────────────────
# Root variables — bootstrap + cluster + platform only (the cicd submodule is
# a separate apply/state at ../cicd/ — see main.tf's file header for why).
# Union of those 3 layers' variables.tf files from the original multi-state
# codebase (01-bootstrap, 02-cluster, 03-platform). Variables the cicd
# submodule needs are declared again in ../cicd/variables.tf — this repo has
# 2 separate Terraform configs, each reading the SAME env/<env>.tfvars file
# (exactly like the original 4-layer design, where one tfvars file already
# served all 4 layers; Terraform simply ignores tfvars keys a given config
# doesn't declare a variable for).
#
# Variables shared across layers with the SAME meaning (region, env, dns_zone,
# eks_cluster_name, cicd_provider, secrets_name, customer_secret_name,
# argocd_ingress_host, route53_zone_id) are declared ONCE here and passed into
# every module block that needs them — see main.tf. The ones also needed
# directly by ../cicd/ (region, env, dns_zone, secrets_name,
# customer_secret_name, argocd_ingress_host, cicd_provider) are simply
# declared again there too — same name, same meaning, separate Terraform
# config, both fed by the same tfvars file.
#
# Variables that existed in a downstream layer ONLY to receive a value already
# produced by an upstream layer (read via `data "terraform_remote_state"` in
# the original codebase — e.g. ssl_certificate_arn) are NOT declared here.
# They're wired automatically module-to-module in main.tf instead; there is
# nothing for a human to set for them. See the comment block in main.tf and
# in each modules/<layer>/variables.tf for the full list.
#
# NAME COLLISION NOTE (eks_cluster_name / route53_zone_id):
#   root var.eks_cluster_name is the BASE cluster name (e.g. "ekai-eks"), fed
#   into module.bootstrap and module.cluster. The platform submodule also
#   declares its OWN "eks_cluster_name" variable, but that one holds the FULL
#   name (<base>-saas-<env>) and is wired from module.cluster.eks_cluster_name's
#   *output* in main.tf below, never from this root variable directly — same
#   name, narrower per-module meaning, not a real ambiguity since Terraform
#   scopes variable names per module, but worth knowing if you're tracing a
#   value.
#
#   Similarly, root var.route53_zone_id is a real user input (used by
#   bootstrap only, and only when manage_dns_zone = false). The platform
#   submodule also declares its own "route53_zone_id" variable, but that one
#   is always wired from module.bootstrap.route53_zone_id's *output* (never
#   from this root variable directly) — that output resolves to whichever
#   zone is actually authoritative (the one Terraform just created, or the
#   pre-existing one you passed in here). ../cicd/variables.tf does NOT
#   redeclare route53_zone_id or ssl_certificate_arn at all — ../cicd/main.tf
#   reads both straight from `data.terraform_remote_state.combined.outputs.*`
#   instead, same as the original 04-cicd/main.tf read them from
#   `data.terraform_remote_state.bootstrap.outputs.*`.
# ──────────────────────────────────────────────────────────────────────────────

# ═══════════════════════════════════════════════════════════════════════════
# Shared across layers (also redeclared in ../cicd/variables.tf where cicd
# needs its own copy — see note above)
# ═══════════════════════════════════════════════════════════════════════════

variable "region" {
  description = "AWS region (e.g. us-east-1). Must match the state bucket region."
  type        = string
}

variable "env" {
  description = "Environment slug (e.g. client1, dev, prod). Used in tags and state key."
  type        = string
}

variable "dns_zone" {
  description = "DNS zone for this env (e.g. client1.ekai.ai). Created by the bootstrap submodule when manage_dns_zone = true."
  type        = string
}

variable "eks_cluster_name" {
  description = "Base EKS cluster name (e.g. \"ekai-eks\") — used to tag subnets for ALB/ELB discovery and as the prefix for the full cluster name (<name>-saas-<env>)."
  type        = string
}

variable "secrets_name" {
  description = "AWS Secrets Manager secret name containing DB credentials + GitHub token. Defaults to <env>-ekai-db-credentials. Ignored when cicd_provider = \"none\" (self-service)."
  type        = string
  default     = ""
}

variable "customer_secret_name" {
  description = "AWS Secrets Manager secret name Terraform creates and holds every env var every service needs (cicd_provider = \"none\" only, created by the cicd submodule). Terraform creates this secret directly — override only if the client wants a different naming convention."
  type        = string
  default     = "ekai-customer"
}

variable "argocd_ingress_host" {
  description = "Hostname for the ArgoCD ingress / the ArgoCD Terraform provider's connection target. Optional — defaults to \"argocd.<dns_zone>\" when omitted."
  type        = string
  default     = null
}

# ── CI/CD provider ─────────────────────────────────────────────────────────────
# NOTE: only cicd_provider = "none" (self-service) is functional in this
# distribution. modules/code_build, modules/github_actions_cicd, and
# modules/amplify_frontend from the source codebase are intentionally not
# included here (see modules/cicd/main.tf's file header) — default changed
# from the source codebase's "codebuild" to "none" accordingly, since this
# repo only ever ships self-service deployments.
variable "cicd_provider" {
  description = <<-EOT
    CI/CD provider for building and pushing Docker images.
      codebuild      — AWS CodeBuild projects with GitHub webhooks.
                       NOT functional in this distribution (module not included).
      github_actions — GitHub Actions workflows with OIDC → IAM role.
                       NOT functional in this distribution (module not included).
      none           — self-service client mode: no CI at all. This is the
                       only supported value in this distribution.
  EOT
  type        = string
  default     = "none"
  validation {
    condition     = contains(["codebuild", "github_actions", "none"], var.cicd_provider)
    error_message = "cicd_provider must be 'codebuild', 'github_actions', or 'none'."
  }
}

# ═══════════════════════════════════════════════════════════════════════════
# bootstrap submodule (Route53 zone + ACM certificate + VPC)
# ═══════════════════════════════════════════════════════════════════════════

variable "manage_dns_zone" {
  description = "If true, the bootstrap submodule creates the Route53 hosted zone. Set false when the zone already exists — pass route53_zone_id instead."
  type        = bool
  default     = true
}

variable "route53_zone_id" {
  description = "Pre-existing Route53 zone ID. Required when manage_dns_zone = false."
  type        = string
  default     = ""
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
}

variable "public_subnet_cidrs" {
  description = "CIDR blocks for public subnets"
  type        = list(string)
}

variable "private_subnet_cidrs" {
  description = "CIDR blocks for private subnets"
  type        = list(string)
  validation {
    condition     = length(var.private_subnet_cidrs) == length(var.public_subnet_cidrs)
    error_message = "private_subnet_cidrs and public_subnet_cidrs must have the same number of entries. The ALB (ArgoCD, app ingress) only ever attaches to public_subnet_cidrs' AZs; if private_subnet_cidrs spans more AZs than that, nodes/pods can land in an AZ the ALB has no subnet in and never receive traffic (ELB target state Target.NotInUse -> 503, even though the pod itself is healthy)."
  }
}

# ═══════════════════════════════════════════════════════════════════════════
# cluster submodule (IAM, EKS, RDS, OIDC provider)
# ═══════════════════════════════════════════════════════════════════════════

variable "cluster_version" {
  description = "Kubernetes version for the EKS cluster. Null → AWS latest."
  type        = string
  default     = null
}

variable "node_min_size" {
  description = "Minimum number of worker nodes"
  type        = number
}

variable "mode_max_size" {
  description = "Maximum number of worker nodes"
  type        = number
}

variable "node_instance" {
  description = "EC2 instance type for worker nodes (e.g., c5.large)"
  type        = string
}

variable "node_ami_type" {
  description = "EKS node group AMI type. AL2023_x86_64_STANDARD required for K8s 1.33+ (AL2 is EOL for 1.33+)."
  type        = string
  default     = "AL2023_x86_64_STANDARD"
}

variable "node_disk_size" {
  description = "Worker node root disk size in GiB."
  type        = number
  default     = 80
}

variable "db_instance_class" {
  description = "RDS instance class (e.g., db.t3.medium)"
  type        = string
}

variable "engine_version" {
  description = "PostgreSQL engine version. AWS periodically drops old minor versions from the supported list (aws rds describe-db-engine-versions --engine postgres) -- check that command if a fresh apply 400s with InvalidParameterCombination."
  type        = string
}

variable "rds_storage_type" {
  description = "RDS storage type (gp2, gp3, io1, ...)."
  type        = string
  default     = "gp2"
}

variable "allocated_storage" {
  description = "Allocated storage in GB for the RDS instance"
  type        = number
}

variable "backup_retention_period" {
  description = "Days to retain automated RDS backups"
  type        = number
}

variable "multi_az" {
  description = "Enable Multi-AZ deployment for RDS"
  type        = bool
}

variable "cloudwatch_namespace" {
  description = "Kubernetes namespace for the CloudWatch addon"
  type        = string
}

variable "eks_public_access_cidrs" {
  description = "CIDRs allowed to reach the EKS public API endpoint"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

# ═══════════════════════════════════════════════════════════════════════════
# platform submodule (ALB controller, ESO, Redis, Neo4j, ArgoCD, KEDA, reloader)
# ═══════════════════════════════════════════════════════════════════════════

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

variable "alb_controller_chart_version" {
  description = "AWS Load Balancer Controller Helm chart version."
  type        = string
  default     = "1.12.0"
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
  description = "StorageClass for the Neo4j PVC (provisioned by the EBS CSI driver addon in the cluster submodule)."
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
