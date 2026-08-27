variable "enabled" {
  description = "Whether to deploy Cluster Autoscaler"
  type        = bool
  default     = true
}

variable "cluster_name" {
  description = "EKS cluster name"
  type        = string
}

variable "aws_region" {
  description = "AWS region where the cluster is deployed"
  type        = string
}

variable "cluster_identity_oidc_issuer" {
  description = "OIDC issuer URL of the EKS cluster"
  type        = string
}

variable "cluster_identity_oidc_issuer_arn" {
  description = "OIDC issuer URL used to construct the IAM OIDC provider ARN"
  type        = string
}

variable "node_group_asg_name" {
  description = "Name of the Auto Scaling Group behind the EKS managed node group — tagged for Cluster Autoscaler's auto-discovery and scoped in its IAM policy"
  type        = string
}

variable "helm_chart_version" {
  description = "Cluster Autoscaler Helm chart version"
  type        = string
  default     = "9.59.0"
}
