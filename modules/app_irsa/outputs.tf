output "service_account_names" {
  description = "Map of pipeline key to Kubernetes ServiceAccount name"
  value       = { for k, sa in kubernetes_service_account.app : k => sa.metadata[0].name }
}

output "role_arns" {
  description = "Map of pipeline key to IAM role ARN"
  value       = { for k, role in aws_iam_role.app : k => role.arn }
}
