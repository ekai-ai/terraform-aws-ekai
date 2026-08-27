# ──────────────────────────────────────────────────────────────────────────────
# Root outputs — two audiences:
#
#   1. End-state values a client actually wants to see after `terraform apply`
#      (argocd_url/admin creds, route53 info, vpc_id, eks_cluster_name, region).
#
#   2. Values ../cicd/'s `data "terraform_remote_state" "combined"` block
#      reads (cluster_endpoint, cluster_ca, aws_account_id, backend/semantics
#      db creds, rds_endpoint, subnet ids, rds_sg_id, oidc_issuer,
#      ssl_certificate_arn, argocd_admin_password_plaintext,
#      redis_credentials, neo4j_credentials, cluster_secret_store_name) —
#      these exist here ONLY because ../cicd/ needs them; a human applying
#      this config alone wouldn't otherwise care. Named to match exactly what
#      the original 03-platform/04-cicd submodule outputs were called, so the
#      remote_state read in ../cicd/main.tf is a direct, traceable rename of
#      `data.terraform_remote_state.cluster.outputs.X` /
#      `data.terraform_remote_state.platform.outputs.X` /
#      `data.terraform_remote_state.bootstrap.outputs.X` →
#      `data.terraform_remote_state.combined.outputs.X`.
#
# portal_url / ekai_files_bucket / customer_secret_arn / customer_secret_name /
# client_iam_policy_for_secret_placeholders moved to ../cicd/outputs.tf — they
# don't exist until the cicd apply runs (this root doesn't deploy the app).
# ──────────────────────────────────────────────────────────────────────────────

output "argocd_url" {
  description = "ArgoCD's public URL."
  value       = "https://${module.platform.argocd_ingress_host}"
}

output "argocd_admin_username" {
  description = "ArgoCD admin username — always literally \"admin\"."
  value       = "admin"
}

output "argocd_admin_password" {
  description = "ArgoCD admin plaintext password (cicd_provider = \"none\" only — self-service generates this directly; non-self-service envs get it from their master Secrets Manager secret instead, not exposed here)."
  value       = module.platform.argocd_admin_password_plaintext
  sensitive   = true
}

output "route53_zone_id" {
  description = "Route53 hosted zone ID actually in use (whichever the bootstrap submodule created or was pointed at)."
  value       = module.bootstrap.route53_zone_id
}

output "route53_zone_name" {
  description = "Route53 hosted zone name."
  value       = module.bootstrap.route53_zone_name
}

output "route53_name_servers" {
  description = "NS records to delegate from the parent zone (e.g. at your domain registrar). Empty when manage_dns_zone = false (you're using a zone that already exists)."
  value       = module.bootstrap.route53_name_servers
}

output "eks_cluster_name" {
  description = "Full EKS cluster name — use with: aws eks update-kubeconfig --name <this> --region <region>"
  value       = module.cluster.eks_cluster_name
}

output "vpc_id" {
  description = "VPC ID. Also read directly from state by scripts/self-deploy-destroy.sh's vpc_cleanup step (cleanup-vpc.sh needs it to find orphaned ALBs/ENIs/SGs blocking VPC teardown)."
  value       = module.bootstrap.vpc_id
}

output "region" {
  description = "AWS region this was deployed into."
  value       = var.region
}

# ═══════════════════════════════════════════════════════════════════════════
# Consumed by ../cicd/'s data "terraform_remote_state" "combined" block only
# ═══════════════════════════════════════════════════════════════════════════

output "cluster_endpoint" {
  description = "EKS API server endpoint. Read by ../cicd/providers.tf's kubernetes/kubectl provider config."
  value       = module.cluster.cluster_endpoint
}

output "cluster_ca" {
  description = "Base64-encoded cluster CA certificate. Read by ../cicd/providers.tf's kubernetes/kubectl provider config."
  value       = module.cluster.cluster_ca
  sensitive   = true
}

output "aws_account_id" {
  description = "AWS account ID. Read by ../cicd/'s customer file-storage S3 bucket naming."
  value       = module.cluster.aws_account_id
}

output "backend_db_username" {
  description = "Backend RDS DB username (cicd_provider = \"none\" only). Read by ../cicd/ to build DATABASE_URL."
  value       = module.cluster.backend_db_username
  sensitive   = true
}

output "backend_db_password" {
  description = "Backend RDS DB password (cicd_provider = \"none\" only). Read by ../cicd/ to build DATABASE_URL."
  value       = module.cluster.backend_db_password
  sensitive   = true
}

output "backend_db_name" {
  description = "Backend RDS DB name (cicd_provider = \"none\" only). Read by ../cicd/ to build DATABASE_URL."
  value       = module.cluster.backend_db_name
}

output "semantics_db_username" {
  description = "Semantics RDS DB username (cicd_provider = \"none\" only). Read by ../cicd/ to build VECTOR_DATABASE_URL."
  value       = module.cluster.semantics_db_username
  sensitive   = true
}

output "semantics_db_password" {
  description = "Semantics RDS DB password (cicd_provider = \"none\" only). Read by ../cicd/ to build VECTOR_DATABASE_URL."
  value       = module.cluster.semantics_db_password
  sensitive   = true
}

output "semantics_db_name" {
  description = "Semantics RDS DB name (cicd_provider = \"none\" only). Read by ../cicd/ to build VECTOR_DATABASE_URL."
  value       = module.cluster.semantics_db_name
}

output "rds_endpoint" {
  description = "RDS PostgreSQL endpoint (host:port). Read by ../cicd/ to build DATABASE_URL/VECTOR_DATABASE_URL."
  value       = module.cluster.rds_endpoint
}

output "public_subnet_ids" {
  description = "Public subnet IDs. Read by ../cicd/ for the ekai-saas chart's Ingress subnets and the code_build/github_actions_cicd module inputs (unused in this distribution, kept for fidelity)."
  value       = module.cluster.public_subnet_ids
}

output "private_subnet_ids" {
  description = "Private subnet IDs. Read by ../cicd/ (code_build/github_actions_cicd module inputs — unused in this distribution, kept for fidelity)."
  value       = module.cluster.private_subnet_ids
}

output "rds_sg_id" {
  description = "RDS security group ID. Read by ../cicd/ (code_build module input — unused in this distribution, kept for fidelity)."
  value       = module.cluster.rds_sg_id
}

output "oidc_issuer" {
  description = "OIDC issuer URL of the EKS cluster. Read by ../cicd/'s app_irsa module for per-service IRSA roles."
  value       = module.cluster.oidc_issuer
}

output "ssl_certificate_arn" {
  description = "Validated ACM wildcard certificate ARN. Read by ../cicd/ for the ekai-saas chart's Ingress and its own aws_route53_record resources."
  value       = module.bootstrap.ssl_certificate_arn
}

output "argocd_admin_password_plaintext" {
  description = "Plaintext ArgoCD admin password (self-service only). Read by ../cicd/main.tf (customer secret's ARGOCD_PASSWORD key) AND by ../cicd/providers.tf's argocd provider config — this is the value that made a same-apply provider.\"argocd\" configuration unsafe, which is exactly why cicd is a separate apply reading it via remote_state instead."
  value       = module.platform.argocd_admin_password_plaintext
  sensitive   = true
}

output "redis_credentials" {
  description = "Redis connection details (empty map when enable_redis = false). Read by ../cicd/ to merge REDIS_* into the customer secret."
  value       = module.platform.redis_credentials
  sensitive   = true
}

output "neo4j_credentials" {
  description = "Neo4j connection details (empty map when enable_neo4j = false). Read by ../cicd/ to merge NEO4J_* into the customer secret."
  value       = module.platform.neo4j_credentials
  sensitive   = true
}

output "cluster_secret_store_name" {
  description = "ClusterSecretStore name. Read by ../cicd/'s ExternalSecret resources."
  value       = module.platform.cluster_secret_store_name
}
