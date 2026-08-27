variable "region" {
  description = "AWS region"
  type        = string
}

variable "env" {
  description = "Environment name (e.g., dev, test, prod)"
  type        = string
}

variable "ekai_namespace" {
  description = "Kubernetes namespace where application ServiceAccounts are created"
  type        = string
}

variable "oidc_issuer_url" {
  description = "OIDC issuer URL of the EKS cluster (e.g. https://oidc.eks.<region>.amazonaws.com/id/<hash>)"
  type        = string
}

variable "pipelines" {
  description = "Map of service pipeline definitions — must match the pipelines var in 04-cicd. Ignored when self_service = true."
  type = map(object({
    branch             = optional(string, null)
    github_repo        = optional(string, null)
    build_cmd          = optional(string, null)
    manifest_folder    = optional(string, "manifest-files")
    manifest_file      = optional(string, null)
    ingresshost        = optional(string, null)
    pre_build_cmds     = optional(list(string), [])
    ecr_repository_url = optional(string, null)
  }))
  default = {}
}

variable "self_service" {
  description = "true for cicd_provider = \"none\" — creates one shared IAM role/ServiceAccount for every service instead of one per pipeline entry, matching the ekai-saas Helm chart's shared secretName/serviceAccountName model."
  type        = bool
  default     = false
}

variable "shared_service_account_name" {
  description = "ServiceAccount name every service runs as (self_service = true only). Must match the Helm chart's serviceAccountName value."
  type        = string
  default     = "ekai-app-sa"
}

variable "customer_secret_name" {
  description = "Secrets Manager secret name the shared IAM role gets read access to (self_service = true only). Must match 04-cicd's var.customer_secret_name."
  type        = string
  default     = ""
}

variable "customer_bucket_arn" {
  description = "ARN of the S3 bucket the shared IAM role gets read/write access to (self_service = true only) — the bucket 04-cicd creates (aws_s3_bucket.ekai_files), not the $${var.env}-ekai-* pattern the per-pipeline role below uses."
  type        = string
  default     = ""
}
