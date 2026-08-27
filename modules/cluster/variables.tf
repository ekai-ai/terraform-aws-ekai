variable "region" {
  description = "AWS region to deploy resources"
  type        = string
}

variable "env" {
  description = "Environment name (e.g., dev, test, prod)"
  type        = string
}

variable "eks_cluster_name" {
  description = "Base name of the EKS cluster (full name: <name>-saas-<env>)"
  type        = string
}

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

variable "secrets_name" {
  description = "AWS Secrets Manager secret name containing DB credentials. Defaults to <env>-ekai-db-credentials. Ignored when cicd_provider = \"none\"."
  type        = string
  default     = ""
}

variable "cicd_provider" {
  description = <<-EOT
    Same value as the cicd submodule's cicd_provider (the root module's single
    tfvars file is shared across all 4 submodules) — only checked here for
    whether it's "none" (self-service: generate RDS credentials directly
    instead of requiring a pre-existing Secrets Manager secret). Which of
    "codebuild"/"github_actions" otherwise makes no difference to this layer.
  EOT
  type        = string
  default     = "none"
  validation {
    condition     = contains(["codebuild", "github_actions", "none"], var.cicd_provider)
    error_message = "cicd_provider must be 'codebuild', 'github_actions', or 'none'."
  }
}

variable "eks_public_access_cidrs" {
  description = "CIDRs allowed to reach the EKS public API endpoint"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

# ── Formerly read via `data "terraform_remote_state" "bootstrap"` ────────────
# Wired automatically from module.bootstrap's outputs by the root module
# (see ../../main.tf) — nothing to set in tfvars for these.

variable "vpc_id" {
  description = "VPC ID (sourced from the bootstrap submodule's output)"
  type        = string
}

variable "vpc_cidr" {
  description = "VPC CIDR block (sourced from the bootstrap submodule's output)"
  type        = string
}

variable "private_subnet_ids" {
  description = "Private subnet IDs (sourced from the bootstrap submodule's output)"
  type        = list(string)
}

variable "public_subnet_ids" {
  description = "Public subnet IDs (sourced from the bootstrap submodule's output) — this layer doesn't consume it directly, only re-exports it for the platform/cicd submodules."
  type        = list(string)
}
