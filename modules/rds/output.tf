output "ekai_saas_db_endpoint" {
  description = "The endpoint of the RDS ekai instance"
  value       = aws_db_instance.ekai_postgresql.endpoint
}

output "rds_SG_ID" {
  description = "The RDS Security groups ID"
  value       = aws_security_group.rds_sg.id
}
output "job_name" {
  value = kubernetes_job.db_init.metadata[0].name
}

output "namespace" {
  value = kubernetes_namespace.ekai_db_init.metadata[0].name
}

# self_service = true only — 04-cicd needs these to build DATABASE_URL/
# VECTOR_DATABASE_URL without reading a master Secrets Manager secret.
output "backend_db_username" {
  value     = local.backend_db_username
  sensitive = true
}

output "backend_db_password" {
  value     = local.backend_db_password
  sensitive = true
}

output "backend_db_name" {
  value = local.backend_db_name
}

output "semantics_db_username" {
  value     = local.semantics_db_username
  sensitive = true
}

output "semantics_db_password" {
  value     = local.semantics_db_password
  sensitive = true
}

output "semantics_db_name" {
  value = local.semantics_db_name
}
