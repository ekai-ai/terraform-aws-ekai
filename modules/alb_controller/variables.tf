variable "enabled" {
  description = "Whether to deploy the ALB controller"
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

variable "helm_chart_name" {
  description = "ALB Controller Helm chart name"
  type        = string
  default     = "aws-load-balancer-controller"
}

variable "helm_chart_release_name" {
  description = "Helm release name for the ALB controller"
  type        = string
  default     = "aws-load-balancer-controller"
}

variable "helm_chart_repo" {
  description = "Helm repository URL for the ALB controller chart"
  type        = string
  default     = "https://aws.github.io/eks-charts"
}

variable "helm_chart_version" {
  description = "AWS Load Balancer Controller Helm chart version."
  type        = string
  default     = "1.12.0"
}

variable "settings" {
  description = "Additional Helm values passed to the ALB controller chart"
  type        = map(any)
  default     = {}
}
