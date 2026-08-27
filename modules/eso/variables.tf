variable "env" {
  description = "Environment name (e.g., dev, test, prod)"
  type        = string
}

variable "region" {
  description = "AWS region"
  type        = string
}

variable "oidc_issuer_url" {
  description = "OIDC issuer URL of the EKS cluster (https://...)"
  type        = string
}

variable "chart_version" {
  description = "ESO Helm chart version"
  type        = string
  default     = "0.10.3"
}

variable "customer_secret_name" {
  description = "Self-service-only customer secret name (e.g. \"ekai-customer\") to additionally grant read access to -- it doesn't follow the \"<env>-*\" naming convention every other secret uses. Blank skips this grant entirely."
  type        = string
  default     = ""
}
