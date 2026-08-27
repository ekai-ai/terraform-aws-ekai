output "cluster_secret_store_name" {
  description = "Name of the ClusterSecretStore CRD (referenced by ExternalSecret resources)"
  value       = "aws-secrets-manager"
}

output "eso_role_arn" {
  description = "ARN of the IRSA role attached to the ESO ServiceAccount"
  value       = aws_iam_role.eso.arn
}
