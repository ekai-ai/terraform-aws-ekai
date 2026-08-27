# ──────────────────────────────────────────────────────────────────────────────
# examples/self-deploy/root/outputs.tf — re-exports every one of
# ../../../outputs.tf's outputs as module.infra.X. See that file for
# descriptions of what each value is and who consumes it.
# ──────────────────────────────────────────────────────────────────────────────

output "argocd_url" {
  description = "ArgoCD's public URL."
  value       = module.infra.argocd_url
}

output "argocd_admin_username" {
  description = "ArgoCD admin username — always literally \"admin\"."
  value       = module.infra.argocd_admin_username
}

output "argocd_admin_password" {
  description = "ArgoCD admin plaintext password (cicd_provider = \"none\" only — self-service generates this directly; non-self-service envs get it from their master Secrets Manager secret instead, not exposed here)."
  value       = module.infra.argocd_admin_password
  sensitive   = true
}

output "route53_zone_id" {
  description = "Route53 hosted zone ID actually in use (whichever the bootstrap submodule created or was pointed at)."
  value       = module.infra.route53_zone_id
}

output "route53_zone_name" {
  description = "Route53 hosted zone name."
  value       = module.infra.route53_zone_name
}

output "route53_name_servers" {
  description = "NS records to delegate from the parent zone (e.g. at your domain registrar). Empty when manage_dns_zone = false (you're using a zone that already exists)."
  value       = module.infra.route53_name_servers
}

output "eks_cluster_name" {
  description = "Full EKS cluster name — use with: aws eks update-kubeconfig --name <this> --region <region>"
  value       = module.infra.eks_cluster_name
}

output "vpc_id" {
  description = "VPC ID. Also read directly from state by scripts/self-deploy-destroy.sh's vpc_cleanup step (cleanup-vpc.sh needs it to find orphaned ALBs/ENIs/SGs blocking VPC teardown)."
  value       = module.infra.vpc_id
}

output "region" {
  description = "AWS region this was deployed into."
  value       = module.infra.region
}

output "cluster_endpoint" {
  description = "EKS API server endpoint. Read by examples/self-deploy/cicd's terraform_remote_state consumer (via the cicd module's own remote_state read) for its kubernetes/kubectl provider config."
  value       = module.infra.cluster_endpoint
}

output "cluster_ca" {
  description = "Base64-encoded cluster CA certificate. Read by examples/self-deploy/cicd's terraform_remote_state consumer for its kubernetes/kubectl provider config."
  value       = module.infra.cluster_ca
  sensitive   = true
}

output "aws_account_id" {
  description = "AWS account ID. Read by the cicd module's customer file-storage S3 bucket naming."
  value       = module.infra.aws_account_id
}

output "backend_db_username" {
  description = "Backend RDS DB username (cicd_provider = \"none\" only). Read by the cicd module to build DATABASE_URL."
  value       = module.infra.backend_db_username
  sensitive   = true
}

output "backend_db_password" {
  description = "Backend RDS DB password (cicd_provider = \"none\" only). Read by the cicd module to build DATABASE_URL."
  value       = module.infra.backend_db_password
  sensitive   = true
}

output "backend_db_name" {
  description = "Backend RDS DB name (cicd_provider = \"none\" only). Read by the cicd module to build DATABASE_URL."
  value       = module.infra.backend_db_name
}

output "semantics_db_username" {
  description = "Semantics RDS DB username (cicd_provider = \"none\" only). Read by the cicd module to build VECTOR_DATABASE_URL."
  value       = module.infra.semantics_db_username
  sensitive   = true
}

output "semantics_db_password" {
  description = "Semantics RDS DB password (cicd_provider = \"none\" only). Read by the cicd module to build VECTOR_DATABASE_URL."
  value       = module.infra.semantics_db_password
  sensitive   = true
}

output "semantics_db_name" {
  description = "Semantics RDS DB name (cicd_provider = \"none\" only). Read by the cicd module to build VECTOR_DATABASE_URL."
  value       = module.infra.semantics_db_name
}

output "rds_endpoint" {
  description = "RDS PostgreSQL endpoint (host:port). Read by the cicd module to build DATABASE_URL/VECTOR_DATABASE_URL."
  value       = module.infra.rds_endpoint
}

output "public_subnet_ids" {
  description = "Public subnet IDs. Read by the cicd module for the ekai-saas chart's Ingress subnets and the code_build/github_actions_cicd module inputs (unused in this distribution, kept for fidelity)."
  value       = module.infra.public_subnet_ids
}

output "private_subnet_ids" {
  description = "Private subnet IDs. Read by the cicd module (code_build/github_actions_cicd module inputs — unused in this distribution, kept for fidelity)."
  value       = module.infra.private_subnet_ids
}

output "rds_sg_id" {
  description = "RDS security group ID. Read by the cicd module (code_build module input — unused in this distribution, kept for fidelity)."
  value       = module.infra.rds_sg_id
}

output "oidc_issuer" {
  description = "OIDC issuer URL of the EKS cluster. Read by the cicd module's app_irsa module for per-service IRSA roles."
  value       = module.infra.oidc_issuer
}

output "ssl_certificate_arn" {
  description = "Validated ACM wildcard certificate ARN. Read by the cicd module for the ekai-saas chart's Ingress and its own aws_route53_record resources."
  value       = module.infra.ssl_certificate_arn
}

output "argocd_admin_password_plaintext" {
  description = "Plaintext ArgoCD admin password (self-service only). Read by the cicd module (customer secret's ARGOCD_PASSWORD key) AND by examples/self-deploy/cicd's argocd provider config — this is the value that makes a same-apply provider \"argocd\" configuration unsafe, which is exactly why cicd is applied separately, reading it back via remote_state instead."
  value       = module.infra.argocd_admin_password_plaintext
  sensitive   = true
}

output "redis_credentials" {
  description = "Redis connection details (empty map when enable_redis = false). Read by the cicd module to merge REDIS_* into the customer secret."
  value       = module.infra.redis_credentials
  sensitive   = true
}

output "neo4j_credentials" {
  description = "Neo4j connection details (empty map when enable_neo4j = false). Read by the cicd module to merge NEO4J_* into the customer secret."
  value       = module.infra.neo4j_credentials
  sensitive   = true
}

output "cluster_secret_store_name" {
  description = "ClusterSecretStore name. Read by the cicd module's ExternalSecret resources."
  value       = module.infra.cluster_secret_store_name
}
