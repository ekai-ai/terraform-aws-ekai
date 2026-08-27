output "eks_cluster_role_arn" {
  description = "ARN of the IAM role assumed by the EKS control plane."
  value       = aws_iam_role.eks_cluster_role.arn
}

# Legacy uppercase name kept for backwards-compat with main.tf
output "NODE_GROUP_ROLE_ARN" {
  description = "ARN of the IAM role attached to EKS managed node groups."
  value       = aws_iam_role.nodes_general.arn
}
