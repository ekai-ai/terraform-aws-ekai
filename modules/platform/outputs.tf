output "cluster_secret_store_name" {
  description = "ClusterSecretStore name used by ExternalSecret resources in 04-cicd"
  value       = module.eso.cluster_secret_store_name
}

output "eso_role_arn" {
  description = "ARN of the ESO IRSA role"
  value       = module.eso.eso_role_arn
}

output "argocd_ingress_host" {
  description = "ArgoCD ingress hostname (consumed by 04-cicd argocd provider)"
  value       = local.argocd_host
}

output "redis_credentials" {
  description = "Redis connection details merged into app secrets by 04-cicd. Empty map when enable_redis = false."
  sensitive   = true
  value = var.enable_redis ? {
    REDIS_HOST     = module.redis[0].redis_host
    REDIS_PORT     = tostring(module.redis[0].redis_port)
    REDIS_USERNAME = module.redis[0].redis_username
    REDIS_PASSWORD = module.redis[0].redis_password
    REDIS_URI      = module.redis[0].redis_uri
  } : {}
}

output "redis_enabled" {
  description = "Whether Redis was deployed in this platform layer."
  value       = var.enable_redis
}

output "neo4j_credentials" {
  description = "Neo4j connection details merged into app secrets by 04-cicd. Empty map when enable_neo4j = false."
  sensitive   = true
  value = var.enable_neo4j ? {
    NEO4J_URI      = module.neo4j[0].bolt_uri
    NEO4J_USERNAME = "neo4j"
    NEO4J_PASSWORD = module.neo4j[0].neo4j_password
  } : {}
}

output "neo4j_enabled" {
  description = "Whether Neo4j was deployed in this platform layer."
  value       = var.enable_neo4j
}

output "argocd_admin_password_plaintext" {
  description = "Plaintext ArgoCD admin password, self_service only (04-cicd's argocd provider needs it to authenticate). Null otherwise — non-self-service envs still get this from the master Secrets Manager secret."
  sensitive   = true
  value       = local.self_service ? random_password.argocd_admin[0].result : null
}
