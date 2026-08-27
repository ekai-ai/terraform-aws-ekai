# ────────────────────────────────────────────────────────────────────────────
# Layer 01 outputs — copy these values into env/<env>.tfvars for 02/03/04.
# ────────────────────────────────────────────────────────────────────────────

output "route53_zone_id" {
  value       = local.zone_id
  description = "Route53 hosted zone ID. Copy to route53_zone_id in tfvars."
}

output "route53_zone_name" {
  value       = local.zone_name
  description = "Route53 hosted zone name."
}

output "route53_name_servers" {
  value       = local.name_servers
  description = "NS records to delegate from the parent zone. Add these to ekai.ai DNS. Empty when manage_dns_zone = false."
}

output "ssl_certificate_arn" {
  value       = aws_acm_certificate_validation.main.certificate_arn
  description = "Validated ACM wildcard certificate ARN (always created by Terraform)."
}

output "vpc_id" {
  value       = module.vpc.vpc_id
  description = "VPC ID — consumed by 02-cluster via terraform_remote_state"
}

output "vpc_cidr" {
  value       = module.vpc.vpc_cidr
  description = "VPC CIDR block"
}

output "public_subnet_ids" {
  value       = module.vpc.public_subnet_ids
  description = "Public subnet IDs"
}

output "private_subnet_ids" {
  value       = module.vpc.private_subnet_ids
  description = "Private subnet IDs"
}
