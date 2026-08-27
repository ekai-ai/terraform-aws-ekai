output "vpc_id" {
  description = "VPC ID (sourced from the bootstrap submodule)"
  value       = var.vpc_id
}

output "vpc_cidr" {
  description = "VPC CIDR block (sourced from the bootstrap submodule)"
  value       = var.vpc_cidr
}

output "private_subnet_ids" {
  description = "Private subnet IDs (sourced from the bootstrap submodule)"
  value       = var.private_subnet_ids
}

output "public_subnet_ids" {
  description = "Public subnet IDs (sourced from the bootstrap submodule)"
  value       = var.public_subnet_ids
}

output "eks_cluster_name" {
  description = "Full EKS cluster name (<base>-saas-<env>)"
  value       = module.eks.eks_cluster_name
}

output "cluster_endpoint" {
  description = "EKS API server endpoint"
  value       = module.eks.cluster_endpoint
}

output "cluster_ca" {
  description = "Base64-encoded cluster CA certificate"
  value       = module.eks.cluster_ca
  sensitive   = true
}

output "oidc_issuer" {
  description = "OIDC issuer URL for the EKS cluster"
  value       = module.eks.oidc_issuer
}

output "oidc_provider_arn" {
  description = "ARN of the IAM OIDC provider (used by IRSA roles in 03-platform + 04-cicd)"
  value       = aws_iam_openid_connect_provider.eks.arn
}

output "node_group_role_arn" {
  description = "ARN of the IAM role attached to worker nodes"
  value       = module.iam.NODE_GROUP_ROLE_ARN
}

output "node_group_asg_name" {
  description = "Name of the Auto Scaling Group behind the EKS managed node group (used by Cluster Autoscaler)"
  value       = module.node_group.asg_name
}

output "rds_endpoint" {
  description = "RDS PostgreSQL endpoint (host:port)"
  value       = module.rds.ekai_saas_db_endpoint
}

output "rds_sg_id" {
  description = "Security group ID of the RDS instance"
  value       = module.rds.rds_SG_ID
}

# cicd_provider = "none" only — 04-cicd builds DATABASE_URL/VECTOR_DATABASE_URL
# from these instead of reading a master Secrets Manager secret.
output "backend_db_username" {
  value     = module.rds.backend_db_username
  sensitive = true
}

output "backend_db_password" {
  value     = module.rds.backend_db_password
  sensitive = true
}

output "backend_db_name" {
  value = module.rds.backend_db_name
}

output "semantics_db_username" {
  value     = module.rds.semantics_db_username
  sensitive = true
}

output "semantics_db_password" {
  value     = module.rds.semantics_db_password
  sensitive = true
}

output "semantics_db_name" {
  value = module.rds.semantics_db_name
}

output "aws_account_id" {
  description = "AWS account ID"
  value       = data.aws_caller_identity.current.account_id
}

output "region" {
  description = "AWS region"
  value       = var.region
}
