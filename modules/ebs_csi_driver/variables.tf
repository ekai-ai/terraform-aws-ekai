variable "env" {
  description = "Environment name (e.g., dev, test, prod)"
  type        = string
}

variable "region" {
  description = "AWS region"
  type        = string
}

variable "eks_cluster_name" {
  description = "EKS cluster name the addon installs into"
  type        = string
}

variable "oidc_issuer_url" {
  description = "OIDC issuer URL of the EKS cluster (https://...)"
  type        = string
}

variable "addon_version" {
  description = "aws-ebs-csi-driver addon version. Leave empty for the latest version EKS supports."
  type        = string
  default     = ""
}
