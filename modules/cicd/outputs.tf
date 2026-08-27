output "ecr_image_map" {
  description = "Map of service name → ECR repository URL. Always empty in this distribution (codebuild/github_actions not included)."
  value       = local.image_map
}

output "cicd_provider" {
  description = "Active CI/CD provider: codebuild or github_actions"
  value       = var.cicd_provider
}

# codebuild/github_actions are not functional in this distribution (see
# main.tf's file header) — modules/github_actions_cicd is not included, so
# this always returns null rather than indexing a nonexistent module.
output "github_actions_role_arn" {
  description = "IAM role ARN for GitHub Actions. Always null in this distribution (module not included)."
  value       = null
}

output "ekai_files_bucket" {
  description = "S3 bucket Terraform created for app file storage (cicd_provider = \"none\" only) — already set as EKAI_BUCKET in the customer secret."
  value       = var.cicd_provider == "none" ? aws_s3_bucket.ekai_files[0].id : null
}

# Added relative to the source codebase's 04-cicd/outputs.tf — no output for
# the customer secret's own ARN/name existed there (only its *contents* were
# referenced downstream). The root module re-exports these so a client can
# find/edit the secret without knowing the naming convention.
output "customer_secret_arn" {
  description = "ARN of the customer application secret Terraform created (cicd_provider = \"none\" only)."
  value       = var.cicd_provider == "none" ? aws_secretsmanager_secret.customer[0].arn : null
}

output "customer_secret_name" {
  description = "Name of the customer application secret Terraform created (cicd_provider = \"none\" only) — same as var.customer_secret_name, re-exported for convenience."
  value       = var.cicd_provider == "none" ? aws_secretsmanager_secret.customer[0].name : null
}

output "client_iam_policy_for_secret_placeholders" {
  description = <<-EOT
    Least-privilege policy JSON for the IAM user the client creates to fill
    AWS_ACCESS_KEY_ID/AWS_SECRET_ACCESS_KEY (S3 + SES — the app's own code
    requires explicit credentials for these, not IRSA) and AWS_SES_FROM_EMAIL
    (cicd_provider = "none" only). Attach this to that IAM user, don't grant
    broader S3/SES access than this.
  EOT
  value = var.cicd_provider == "none" ? jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "EkaiFileStorage"
        Effect   = "Allow"
        Action   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject", "s3:ListBucket"]
        Resource = [aws_s3_bucket.ekai_files[0].arn, "${aws_s3_bucket.ekai_files[0].arn}/*"]
      },
      {
        Sid      = "EkaiSendEmail"
        Effect   = "Allow"
        Action   = ["ses:SendEmail", "ses:SendRawEmail"]
        Resource = "*"
      }
    ]
  }) : null
}
