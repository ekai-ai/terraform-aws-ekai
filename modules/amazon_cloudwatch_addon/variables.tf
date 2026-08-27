variable "eks_cluster_name" {
  description = "Name of the EKS cluster to attach the CloudWatch addon to"
  type        = string
}

variable "region" {
  description = "AWS region"
  type        = string
}

variable "cloudwatch_namespace" {
  description = "Kubernetes namespace for the CloudWatch agent"
  type        = string
}
