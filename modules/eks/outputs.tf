output "eks_cluster_name" {
  description = "Name of the EKS cluster"
  value       = aws_eks_cluster.eks.name
}

output "cluster_endpoint" {
  description = "EKS cluster API endpoint"
  value       = aws_eks_cluster.eks.endpoint
}

# Alias kept for any existing references
output "eks_cluster_endpoint" {
  description = "EKS cluster API endpoint (alias for cluster_endpoint)"
  value       = aws_eks_cluster.eks.endpoint
}

output "cluster_ca" {
  description = "Base64-encoded cluster certificate authority data"
  value       = aws_eks_cluster.eks.certificate_authority[0].data
}

output "oidc_issuer" {
  description = "OIDC issuer URL for the EKS cluster"
  value       = aws_eks_cluster.eks.identity[0].oidc[0].issuer
}
