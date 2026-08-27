output "redis_host" {
  description = "In-cluster DNS name for the Redis master service."
  value       = local.redis_host
}

output "redis_port" {
  description = "Redis port (6379)."
  value       = local.redis_port
}

output "redis_username" {
  description = "Redis ACL user (always 'default' for Bitnami chart with sentinel disabled)."
  value       = "default"
}

output "redis_password" {
  description = "Redis password for the default user."
  value       = random_password.redis.result
  sensitive   = true
}

output "redis_uri" {
  description = "\"<host>:<port>\", no scheme, no embedded credentials -- matches REDIS_URI as used in real Ekai secrets."
  value       = local.redis_uri
}
