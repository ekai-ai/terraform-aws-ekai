# ──────────────────────────────────────────────────────────────────────────────
# cicd outputs — re-exports module.cicd's own outputs. portal_url lives here
# (not in ../outputs.tf) because it isn't real until THIS apply has run — the
# combined root doesn't deploy the application, only the platform it runs on.
#
# ArgoCD's own URL/admin credentials are already available from the combined
# root's outputs (`terraform output` in the parent directory) — ArgoCD itself
# is deployed there, not here — so they aren't duplicated in this file.
# ──────────────────────────────────────────────────────────────────────────────

output "portal_url" {
  description = "The application's public URL (cicd_provider = \"none\" only)."
  value       = var.cicd_provider == "none" ? "https://portal.${var.dns_zone}" : null
}

output "ekai_files_bucket" {
  description = "S3 bucket Terraform created for the application's file storage (cicd_provider = \"none\" only)."
  value       = module.cicd.ekai_files_bucket
}

output "customer_secret_arn" {
  description = "ARN of the customer application secret Terraform created (cicd_provider = \"none\" only) — edit this to fill in the REPLACE_ME placeholders (LLM API keys, Cognito, SES/S3 IAM user, etc.)."
  value       = module.cicd.customer_secret_arn
}

output "customer_secret_name" {
  description = "Name of the customer application secret Terraform created (cicd_provider = \"none\" only)."
  value       = module.cicd.customer_secret_name
}

output "client_iam_policy_for_secret_placeholders" {
  description = "Least-privilege IAM policy JSON for the IAM user you create to fill AWS_ACCESS_KEY_ID/AWS_SECRET_ACCESS_KEY/AWS_SES_FROM_EMAIL in the customer secret (cicd_provider = \"none\" only)."
  value       = module.cicd.client_iam_policy_for_secret_placeholders
}

output "ecr_image_map" {
  description = "Map of service name → ECR repository URL. Always empty in this distribution (codebuild/github_actions not included)."
  value       = module.cicd.ecr_image_map
}

output "cicd_provider" {
  description = "Active CI/CD provider."
  value       = module.cicd.cicd_provider
}
