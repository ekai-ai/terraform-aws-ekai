# ──────────────────────────────────────────────────────────────────────────────
# cicd variables — the subset of modules/cicd's variables that are genuine
# human/tfvars inputs (matches the "own variables" section of
# modules/cicd/variables.tf exactly). Everything modules/cicd needs that used
# to come from `data "terraform_remote_state" "cluster"` / "platform" /
# "bootstrap" is NOT declared here — main.tf reads those directly from
# `data.terraform_remote_state.combined.outputs.*` instead and passes them
# straight into the module "cicd" call.
#
# This file is read from the SAME env/<env>.tfvars file the combined root
# (../variables.tf) reads — region/env/dns_zone/secrets_name/
# customer_secret_name/argocd_ingress_host/cicd_provider are declared again
# here (same name, same meaning) because this is a separate Terraform config
# with its own variable namespace, not because the value differs.
# ──────────────────────────────────────────────────────────────────────────────

variable "region" {
  description = "AWS region"
  type        = string
}

variable "env" {
  description = "Environment name (e.g., dev, test, prod)"
  type        = string
}

variable "argocd_ingress_host" {
  description = "ArgoCD server hostname — used by the ArgoCD Terraform provider to connect (e.g. argocd.client1.ekai.ai). Optional — defaults to \"argocd.<dns_zone>\" when omitted."
  type        = string
  default     = null
}

variable "dns_zone" {
  description = "Base DNS zone for this environment (e.g. dev-eks.ekai.ai). Used to derive argocd_ingress_host, ekai_web_ingresshost, and per-service ingresshost when not explicitly set."
  type        = string
}

variable "secrets_name" {
  description = "AWS Secrets Manager secret name containing DB credentials + GitHub token. Defaults to <env>-ekai-db-credentials."
  type        = string
  default     = ""
}

variable "customer_secret_name" {
  description = "AWS Secrets Manager secret name Terraform creates and holds every env var every service needs (cicd_provider = \"none\" only). Terraform creates this secret directly — override only if the client wants a different naming convention."
  type        = string
  default     = "ekai-customer"
}

variable "shared_service_account_name" {
  description = "ServiceAccount every service runs as (cicd_provider = \"none\" only). Must match the ekai-saas Helm chart's serviceAccountName value."
  type        = string
  default     = "ekai-app-sa"
}

variable "image_tag" {
  description = "Application image tag to deploy (cicd_provider = \"none\" only) — passed through as the ekai-saas chart's imageTag."
  type        = string
  default     = ""
}

variable "erd_storage_class" {
  description = "StorageClass for ERD's workspace PVC (cicd_provider = \"none\" only) — passed through as the ekai-saas chart's erd.workspace.storageClassName."
  type        = string
  default     = "gp3"
}

variable "ingress_class_name" {
  description = "Ingress controller class for the ekai-saas chart (cicd_provider = \"none\" only) — \"alb\", \"nginx\", \"gce\", \"azure-application-gateway\", etc. Only \"alb\" wires shared_alb_name/certificateArn/subnets below; other controllers need ingress.annotations set separately via a values override."
  type        = string
  default     = "alb"
}

variable "shared_alb_name" {
  description = "Name of the shared ALB the ekai-saas chart's Ingress creates (cicd_provider = \"none\", ingress_class_name = \"alb\" only). Also what wait_for_alb polls for and aws_route53_record.services points DNS at. Defaults to \"ekai<env>-shared-alb\"."
  type        = string
  default     = ""
}

variable "use_minio" {
  description = "Whether the app should use a MinIO/S3-compatible endpoint instead of real AWS S3 for file storage (cicd_provider = \"none\" only). Terraform does not deploy MinIO either way — true only makes sense if the client runs their own and fills MINIO_ENDPOINT_URL/MINIO_ACCESS_KEY/MINIO_SECRET_ACCESS_KEY via the secret-update CLI command afterward."
  type        = bool
  default     = false
}

variable "claude_model" {
  description = "Claude model the app's semantics service uses (cicd_provider = \"none\" only)."
  type        = string
  default     = "claude-haiku-4-5-20251001"
}

variable "vector_embedding_model" {
  description = "OpenAI embedding model for semantics' vector search (cicd_provider = \"none\" only)."
  type        = string
  default     = "text-embedding-3-small"
}

variable "vector_embedding_batch_size" {
  description = "Batch size for embedding generation (cicd_provider = \"none\" only)."
  type        = number
  default     = 100
}

variable "secret_recovery_window_days" {
  description = "Recovery window before the customer secret is permanently deleted after a `terraform destroy` (cicd_provider = \"none\" only). 0 = delete immediately, so a re-apply with the same customer_secret_name doesn't fail for up to 30 days. Raise this for extra accidental-deletion protection once past initial testing."
  type        = number
  default     = 0
}

variable "secret_value_overrides" {
  description = "Escape hatch for any key in the customer secret (cicd_provider = \"none\" only) that doesn't have its own dedicated variable — merged on top of every computed/default value, so it wins on conflicts. E.g. { SEMANTICS__DOCUMENT_CHUNK_SIZE = \"50000\" }. Same effect as editing the secret via the AWS CLI after apply, but survives a full destroy/re-apply."
  type        = map(string)
  default     = {}
}

variable "manifest_folder" {
  description = "Folder inside deployment-files repo where K8s manifests live (e.g. aws-manifests, manifest-files)"
  type        = string
  default     = "manifest-files"
}

# ── CI/CD provider ─────────────────────────────────────────────────────────────
# NOTE: only cicd_provider = "none" (self-service) is functional in this
# distribution — see ../main.tf's file header. The "codebuild"/"github_actions"
# values are left in the validation below as harmless dead code (matches the
# source codebase this was restructured from) but selecting either will not
# actually build/push anything: modules/code_build and modules/github_actions_cicd
# are not included in this repo.
variable "cicd_provider" {
  description = <<-EOT
    CI/CD provider for building and pushing Docker images.
      codebuild      — AWS CodeBuild projects with GitHub webhooks (AWS-native).
                       NOT functional in this distribution (module not included).
      github_actions — GitHub Actions workflows with OIDC → IAM role (no CodeBuild).
                       NOT functional in this distribution (module not included).
      none           — self-service client mode: no CI at all. Images come from
                       existing_ecr_base_url (Ekai-published, cross-account
                       pull); ArgoCD deploys the ekai-saas Helm chart Ekai
                       maintains instead of a git-based manifest patch. See
                       helm_chart_repo_url/helm_chart_version. This is the
                       only supported value in this distribution.
  EOT
  type        = string
  default     = "none"
  validation {
    condition     = contains(["codebuild", "github_actions", "none"], var.cicd_provider)
    error_message = "cicd_provider must be 'codebuild', 'github_actions', or 'none'."
  }
}

variable "helm_chart_repo_url" {
  description = "OCI registry Ekai publishes the ekai-saas chart to (cicd_provider = \"none\" only), e.g. \"public.ecr.aws/s7m9t1b0/ekai-helm\" -- bare host+path, no \"oci://\" prefix and no chart name suffix (that's helm_chart_name). Expected public — no client credentials needed."
  type        = string
  default     = ""
}

variable "helm_chart_version" {
  description = "Chart version to deploy (cicd_provider = \"none\" only). Defaults to \"*\" — ArgoCD always tracks and auto-syncs whatever version is latest in the Helm repo, no terraform apply needed per release. Set an exact version (e.g. \"0.1.2\") to pin instead."
  type        = string
  default     = "*"
}

variable "pipelines" {
  description = "Map of service definitions. branch/github_repo/build_cmd/manifest_file are only needed for cicd_provider \"codebuild\"/\"github_actions\" (not functional in this distribution) — omit them for cicd_provider = \"none\"."
  type = map(object({
    branch             = optional(string, null)
    github_repo        = optional(string, null)
    build_cmd          = optional(string, null)
    manifest_folder    = optional(string, "manifest-files") # folder inside deployment-files repo
    manifest_file      = optional(string, null)
    ingresshost        = optional(string, null) # defaults to "<name-without-ekai->.<dns_zone>" when omitted
    pre_build_cmds     = optional(list(string), [])
    ecr_repository_url = optional(string, null)
  }))
  default = {}
}

variable "CD_branch" {
  description = "Branch in deployment-files repo used for CD manifests. Only read when cicd_provider != \"none\" — a self-service client has no default, doesn't need to set this."
  type        = string
  default     = ""
}

variable "github_org" {
  description = "GitHub organisation name. Only read when cicd_provider != \"none\" — a self-service client has no default, doesn't need to set this."
  type        = string
  default     = ""
}

variable "ekai_namespace" {
  description = "Kubernetes namespace for ekai application services"
  type        = string
}

variable "ekai_web_branch" {
  description = "Git branch for the Amplify frontend. Not functional in this distribution (modules/amplify_frontend not included) — a self-service client's frontend runs from the ekai-saas chart instead, doesn't need to set this."
  type        = string
  default     = ""
}

variable "ekai_web_ingresshost" {
  description = "Ingress hostname for the frontend. Not functional in this distribution (modules/amplify_frontend not included). Optional — defaults to \"console.<dns_zone>\" when omitted."
  type        = string
  default     = null
}

variable "ekai_web_env" {
  description = "Environment variables injected into the Amplify frontend build. Not functional in this distribution (modules/amplify_frontend not included)."
  type        = map(string)
  default     = {}
}

variable "create_github_oidc_provider" {
  description = "Create the GitHub Actions OIDC provider in IAM. Not functional in this distribution (modules/github_actions_cicd not included)."
  type        = bool
  default     = true
}

variable "create_ecr" {
  description = "When true, creates ECR repos for pipelines that have no ecr_repository_url. Not functional in this distribution (modules/code_build and modules/github_actions_cicd not included) — self-service always pulls from existing_ecr_base_url."
  type        = bool
  default     = true
}

variable "existing_ecr_base_url" {
  description = "Used when create_ecr = false and a pipeline has no ecr_repository_url. Images are expected at <existing_ecr_base_url>/<env>-<service>. Example: 123456789.dkr.ecr.eu-central-1.amazonaws.com. Also the imageRegistry passed to the ekai-saas chart for cicd_provider = \"none\"."
  type        = string
  default     = null
}
