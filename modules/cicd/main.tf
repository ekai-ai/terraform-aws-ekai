# ──────────────────────────────────────────────────────────────────────────────
# Layer 04 — CI/CD
# Depends on the cluster and platform submodules (wired by the root module —
# see ../../main.tf — instead of terraform_remote_state reads, since this is
# now one apply/one state).
# Provisions ECR repos, CI pipelines (CodeBuild OR GitHub Actions), Amplify
# frontend, ArgoCD Applications, and ExternalSecret CRDs.
#
# Per-service Secrets Manager secrets ({env}-ekai-<service>) are created and
# owned by the client — same pattern as Azure per-service Key Vault secrets.
# Ekai provides DATABASE_URL and REDIS_* values after 02-cluster + 03-platform
# apply; client adds them to their Secrets Manager secret before first build.
#
# THIS DISTRIBUTION ONLY PORTS THE SELF-SERVICE (cicd_provider = "none") PATH
# ───────────────────────────────────────────────────────────────────────────
# The source codebase this was restructured from also supports cicd_provider
# = "codebuild" / "github_actions" (Ekai-internal environments only) via the
# modules/code_build, modules/github_actions_cicd, and modules/amplify_frontend
# modules. Those three modules are intentionally NOT included in this repo's
# modules/ directory (see repo root README), so the module blocks that used
# to invoke them have been removed here rather than left in place — leaving
# them would break `terraform init` for every user of this repo (a module
# block's `source` must resolve even when its `count` evaluates to 0). The
# cicd_provider variable, its "codebuild"/"github_actions" validation, and a
# few other non-self-service variables/data sources are still left in place
# as harmless dead code (see variables.tf) — only the module blocks that
# require the un-ported modules were removed.
# ──────────────────────────────────────────────────────────────────────────────

# ── Master credentials from Secrets Manager — self_service skips this
# entirely: no pre-existing secret required, 02-cluster/03-platform generate
# DB creds and the ArgoCD password directly instead. ───────────────────────
locals {
  secrets_name = var.secrets_name != "" ? var.secrets_name : "${var.env}-ekai-db-credentials"

  # One source of truth for "is this a self-service deploy" — every
  # cicd_provider == "none" check below reads this instead, so there's one
  # place to fix if the provider values or self-service condition ever change.
  self_service = var.cicd_provider == "none"
}

data "aws_secretsmanager_secret_version" "ekai_db" {
  count     = local.self_service ? 0 : 1
  secret_id = local.secrets_name
}

locals {
  _secret               = local.self_service ? {} : jsondecode(data.aws_secretsmanager_secret_version.ekai_db[0].secret_string)
  argocd_admin_password = local.self_service ? var.argocd_admin_password_plaintext : local._secret["argocd_admin_password"]
  # Unused for self_service — code_build/github_actions_cicd/amplify_frontend
  # are all skipped, and ekai_CD's git repo credentials only exist when
  # source_type == "git". No need to read them from anywhere.
  github_token        = local.self_service ? "" : local._secret["github_token"]
  github_username     = local.self_service ? "" : local._secret["github_username"]
  github_email        = local.self_service ? "" : local._secret["github_email"]
  ssl_certificate_arn = var.ssl_certificate_arn
  route53_zone_id     = var.route53_zone_id

  argocd_host = coalesce(var.argocd_ingress_host, "argocd.${var.dns_zone}")
  web_host    = coalesce(var.ekai_web_ingresshost, "console.${var.dns_zone}")

  # cicd_provider = "none" only — referenced by self_service_helm_values,
  # wait_for_alb, and data.aws_lb.ekai_shared below; one source of truth
  # instead of the same string literal repeated in all three.
  shared_alb_name = coalesce(var.shared_alb_name, "ekai${var.env}-shared-alb")

  # Any pipeline entry that omits ingresshost gets "<name-without-ekai->.<dns_zone>"
  # (e.g. "ekai-backend" -> "backend.<dns_zone>"). Explicit values (e.g. client1's
  # "api.client1.ekai.ai" override) always win — this only fills in the gap.
  resolved_pipelines = {
    for svc, cfg in var.pipelines : svc => merge(cfg, {
      ingresshost = coalesce(cfg.ingresshost, "${trimprefix(svc, "ekai-")}.${var.dns_zone}")
    })
  }
}

# ── cicd_provider = "none" only: Terraform CREATES the customer's application
# secret directly — no more requiring the client to pre-create it with a
# placeholder JSON before terraform apply. Every value Terraform can know for
# certain (RDS/Redis/Neo4j creds, service URLs derived from dns_zone, freshly
# generated crypto keys, a real S3 bucket it also creates below, and safe
# non-secret defaults verified end-to-end against a real running stack) is
# filled in for real — the app needs to actually work for the client, not
# just boot. LLM keys/Cognito/GitHub App/Document AI are left blank ("") --
# out of scope for this pass, same as GitHub sync. The only values that
# genuinely require the client's own external account and are needed for
# the app to function out of the box are an IAM user with S3/SES access,
# left as "REPLACE_ME". Update those after apply with (see the
# `client_iam_policy_for_secret_placeholders` output for the IAM user's
# S3/SES policy):
#   aws secretsmanager get-secret-value --secret-id <name> --query SecretString --output text \
#     | jq '.AWS_ACCESS_KEY_ID = "..." | .AWS_SECRET_ACCESS_KEY = "..." | .AWS_SES_FROM_EMAIL = "..."' \
#     | aws secretsmanager put-secret-value --secret-id <name> --secret-string file:///dev/stdin
# lifecycle.ignore_changes means Terraform only sets this content once, at
# creation — it never overwrites whatever the client puts there afterward.
resource "random_id" "encryption_key" {
  count       = local.self_service ? 1 : 0
  byte_length = 32
}

resource "random_id" "jwt_secret" {
  count       = local.self_service ? 1 : 0
  byte_length = 32
}

resource "random_id" "fernet_key" {
  count       = local.self_service ? 1 : 0
  byte_length = 32
}

# Real S3 bucket for app file storage — created regardless of var.use_minio,
# since it's cheap and gives a working AWS_ACCESS_KEY_ID/SECRET target even
# if the client later switches to MinIO. Bucket names must be globally
# unique across all of AWS, not just this account — account_id makes this
# reliably so (02-cluster already exports it, no need for a second STS call).
resource "aws_s3_bucket" "ekai_files" {
  count  = local.self_service ? 1 : 0
  bucket = "ekai-${var.env}-${var.aws_account_id}"
  # Matches secret_recovery_window_days = 0's "clean teardown" intent — once
  # the app has actually written files, a plain `terraform destroy` fails
  # with BucketNotEmpty otherwise, and nothing else in this stack empties it.
  force_destroy = true
}

resource "aws_s3_bucket_public_access_block" "ekai_files" {
  count                   = local.self_service ? 1 : 0
  bucket                  = aws_s3_bucket.ekai_files[0].id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "ekai_files" {
  count  = local.self_service ? 1 : 0
  bucket = aws_s3_bucket.ekai_files[0].id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

locals {
  # Matches the real, verified secret shape — DATABASE_URL for backend's own
  # database.
  # self_service: 02-cluster generates these directly (module.rds's
  # self_service branch) and exports them via remote state — no master
  # secret involved at all, unlike the non-self-service path below.
  generated_db_urls = local.self_service ? {
    DATABASE_URL = "postgresql://${var.backend_db_username}:${var.backend_db_password}@${var.rds_endpoint}/${var.backend_db_name}"
  } : {}

  generated_redis_creds = local.self_service ? var.redis_credentials : {}
  generated_neo4j_creds = local.self_service ? var.neo4j_credentials : {}

  # Not one of the app's 84 documented keys — the client's own convenience,
  # so they can find their generated ArgoCD login the same place as
  # everything else instead of running a separate `terraform output` on
  # 03-platform. ArgoCD's admin username is always literally "admin".
  generated_argocd_creds = local.self_service ? {
    ARGOCD_USERNAME = "admin"
    ARGOCD_PASSWORD = local.argocd_admin_password
  } : {}

  # AI_CORE_ENDPOINT is called by the BACKEND pod itself, server-to-server --
  # same mistake as the FRONTEND__ URLs below, just one layer deeper:
  # pointing it at the public Ingress hostname sends the backend's own
  # traffic out through the internet-facing ALB and back in (AWS ALB
  # hairpin routing), which surfaced as intermittent 503s even though the
  # same hostname works fine from an external browser.
  # local-deployment/.env.example already gets this right (http://ekai-erd:9002,
  # a Docker Compose network alias) -- the K8s equivalent is the in-cluster
  # Service DNS name (port matches the chart's values.yaml erd.api.containerPort
  # default; this layer has no visibility into that default today, so it's
  # hardcoded here same as local-deployment's .env.example hardcodes it).
  #
  # FRONTEND_URL stays the real public URL (used for outbound things like
  # email links, not API calls).
  #
  # FRONTEND__*_URL (except GITHUB_SYNC_APP_URL, see client_provided_
  # placeholders below) are different again: they're read by the
  # *browser-side* JS bundle, and the frontend's nginx image bakes in a
  # strict `connect-src 'self'` CSP plus its own internal reverse-proxy
  # (/api/, /api/ai_core_ms/ -> the same backend/erd K8s Services). Absolute
  # cross-subdomain URLs here get silently blocked client-side by CSP
  # ("Network Error" on login/register, no server-side error at all) --
  # must be relative paths so the browser stays same-origin and nginx does
  # the actual cross-service hop.
  generated_service_urls = local.self_service ? {
    FRONTEND_URL          = "https://portal.${var.dns_zone}"
    AI_CORE_ENDPOINT      = "http://ekai-erd:9002"
    FRONTEND__BACKEND_URL = "/api/"
    FRONTEND__AI_CORE_URL = "/api/ai_core_ms/"
  } : {}

  # Freshly generated per-install, independent values — never reused across
  # environments (unlike the real dev secret, which reuses one value for all
  # three; that's not worth copying).
  #
  # ENCRYPTION_KEY/PLATFORM__FERNET_KEY get a "=" appended: random_id's
  # b64_url for byte_length=32 is unpadded base64 (43 chars) — verified with
  # a real Fernet decode that both Python's cryptography and the Fernet spec
  # itself require the padded 44-char form ("Fernet key must be 32 url-safe
  # base64-encoded bytes"), and both keys are fed straight into Fernet
  # (ai-core's crypto.py, backend's encryption-fernet.ts). 32 bytes always
  # needs exactly one padding character, so this is exact, not a guess.
  # PLATFORM__JWT_SECRET has no such format requirement — left as-is.
  generated_crypto_keys = local.self_service ? {
    ENCRYPTION_KEY       = "${random_id.encryption_key[0].b64_url}="
    PLATFORM__JWT_SECRET = random_id.jwt_secret[0].b64_url
    PLATFORM__FERNET_KEY = "${random_id.fernet_key[0].b64_url}="
  } : {}

  # Safe, non-secret, working defaults — same for every install, verified
  # end-to-end against a real running stack. The client never needs to touch
  # these.
  safe_defaults = local.self_service ? {
    EKAI_BUCKET                 = aws_s3_bucket.ekai_files[0].id
    DECRYPTED_EKAI_TOKEN        = "EKAI@8008"
    USE_MINIO                   = tostring(var.use_minio)
    AWS_REGION                  = var.region
    AWS_REGISTRY_REGION         = var.region
    AWS_ECR_REGISTRY            = var.existing_ecr_base_url
    SES_AWS_REGION              = var.region
    NODE_ENV                    = "production"
    ENVIRONMENT                 = "production"
    PORT                        = "3000"
    PLATFORM__PORT              = "3000"
    CONFIG_ROOT                 = "/app/config"
    PLATFORM__APPLICATION_NAME  = "ekai"
    PLATFORM__DISABLE_SAME_SITE = "false"
    AI_CORE__BASE_PATH          = "/app/workspaces"
    AI_CORE__REDIS_DB           = "0"
    AI_CORE__REDIS_BUFFER_TIME  = "60"
    LOGS_GROUP_NAME             = "ekai/${var.env}"
  } : {}

  # Only the client can provide these — real external accounts/keys Terraform
  # has no way to know. Blank string for genuinely optional features
  # (GitHub sync); "REPLACE_ME" for ones the app needs to actually function.
  client_provided_placeholders = local.self_service ? {
    PLATFORM__EKAI_GITHUB_APP_ID          = ""
    PLATFORM__EKAI_GITHUB_APP_PRIVATE_KEY = ""
    # Not a backend call -- the public github.com/apps/.../installations/new
    # install link, only needed if testing the GitHub sync flow.
    FRONTEND__GITHUB_SYNC_APP_URL = ""

    AWS_ACCESS_KEY_ID     = "REPLACE_ME"
    AWS_SECRET_ACCESS_KEY = "REPLACE_ME"
    AWS_SES_FROM_EMAIL    = "REPLACE_ME"
  } : {}
}

resource "aws_secretsmanager_secret" "customer" {
  count = local.self_service ? 1 : 0
  name  = var.customer_secret_name
  # Matches self-deploy-destroy.sh's --force-delete-without-recovery for
  # this same kind of secret by default (var.secret_recovery_window_days = 0) —
  # without this, destroying and re-applying reuses the same name and fails
  # for up to 30 days (AWS's default recovery window blocks recreating a
  # secret still pending deletion).
  recovery_window_in_days = var.secret_recovery_window_days
}

resource "aws_secretsmanager_secret_version" "customer" {
  count     = local.self_service ? 1 : 0
  secret_id = aws_secretsmanager_secret.customer[0].id

  # secret_value_overrides is merged LAST, so it wins on any key conflict —
  # the one place left to override a value with no dedicated variable
  # without editing this file.
  secret_string = jsonencode(merge(
    local.client_provided_placeholders,
    local.safe_defaults,
    local.generated_service_urls,
    local.generated_crypto_keys,
    local.generated_db_urls,
    local.generated_redis_creds,
    local.generated_neo4j_creds,
    local.generated_argocd_creds,
    var.secret_value_overrides,
  ))

  lifecycle {
    ignore_changes = [secret_string]
    precondition {
      # 03-platform's enable_redis/enable_neo4j default to false and aren't
      # forced true for cicd_provider = "none" — a self-service tfvars that
      # forgets either (unlike env/acme.tfvars, which sets both) would
      # otherwise ship a customer secret silently missing REDIS_*/NEO4J_*
      # keys entirely, only surfacing as a pod crash much later.
      condition     = length(local.generated_redis_creds) > 0 && length(local.generated_neo4j_creds) > 0
      error_message = "cicd_provider = \"none\" requires 03-platform's enable_redis = true and enable_neo4j = true — the ekai-saas chart's ERD/KEDA needs both, and this secret would otherwise be missing REDIS_*/NEO4J_* keys entirely."
    }
    precondition {
      # Both flow into self_service_helm_values (imageRegistry/the chart
      # repo ArgoCD pulls from) — blank here means a chart the client can
      # never actually pull, failing confusingly inside ArgoCD instead of
      # at plan time.
      condition     = var.existing_ecr_base_url != null && var.existing_ecr_base_url != "" && var.helm_chart_repo_url != ""
      error_message = "cicd_provider = \"none\" requires existing_ecr_base_url and helm_chart_repo_url to both be set."
    }
  }
}

# Every field from the ekai-saas chart's example-values.yaml, sourced from
# what this Terraform layer already knows — nothing left for the chart's own
# (non-functional) blank defaults to fill in.
locals {
  self_service_helm_values = local.self_service ? yamlencode({
    namespace          = var.ekai_namespace
    dnsZone            = var.dns_zone
    imageRegistry      = var.existing_ecr_base_url
    imageTag           = var.image_tag
    secretName         = var.customer_secret_name
    serviceAccountName = var.shared_service_account_name
    erd = {
      workspace = {
        storageClassName = var.erd_storage_class
      }
    }
    ingress = {
      className      = var.ingress_class_name
      albName        = local.shared_alb_name
      certificateArn = local.ssl_certificate_arn
      subnets        = join(",", var.public_subnet_ids)
    }
  }) : ""
}

# ── CI/CD Provider: CodeBuild / GitHub Actions ────────────────────────────────
# Not ported to this distribution — see the file header above. count = 0
# always in self-service; module.code_build / module.github_actions_cicd
# blocks were removed rather than kept with count = 0 (their module source
# directories don't exist in this repo).
locals {
  # Was: cicd_provider == "codebuild" ? module.code_build[0].ecr_image_map :
  #      cicd_provider == "github_actions" ? module.github_actions_cicd[0].image_map :
  #      {}
  # Both branches are unreachable in this distribution (their modules are not
  # included), so this collapses to the cicd_provider = "none" case directly.
  image_map = {} # cicd_provider = "none" — no CI, nothing builds/tags images here
}

# ArgoCD's own sync (CreateNamespace=true, see module.ekai_CD below) would
# eventually create this namespace too, but only asynchronously once it
# actually syncs -- not in time for the ExternalSecret/ServiceAccount
# resources below, which need it to exist in THIS apply. Idempotent either
# way: ArgoCD's CreateNamespace is a no-op once this already exists.
resource "kubernetes_namespace" "ekai_app" {
  metadata {
    name = var.ekai_namespace
  }
}

# ── ExternalSecret CRDs — ESO syncs client-managed secrets into K8s ──────────
# codebuild/github_actions: one per service. Client creates {env}-ekai-<service>
# in Secrets Manager with that service's env vars (DATABASE_URL, REDIS_URL,
# API_KEY etc.). ESO reads and injects into pods.
resource "kubectl_manifest" "external_secret" {
  for_each = var.cicd_provider != "none" ? local.resolved_pipelines : {}

  yaml_body = yamlencode({
    apiVersion = "external-secrets.io/v1beta1"
    kind       = "ExternalSecret"
    metadata = {
      name      = "${each.key}-env"
      namespace = var.ekai_namespace
    }
    spec = {
      refreshInterval = "1m"
      secretStoreRef = {
        name = var.cluster_secret_store_name
        kind = "ClusterSecretStore"
      }
      target = {
        name           = "${each.key}-env"
        creationPolicy = "Owner"
      }
      dataFrom = [{
        extract = {
          key = "${var.env}-${each.key}"
        }
      }]
    }
  })

  depends_on = [kubernetes_namespace.ekai_app]
}

# cicd_provider = "none" (self-service): one shared ExternalSecret for every
# service, matching the ekai-saas Helm chart's shared secretName. Client
# creates ONE Secrets Manager secret (var.customer_secret_name — set this
# explicitly in tfvars) with every env var every service needs, instead of
# one secret per service.
resource "kubectl_manifest" "external_secret_shared" {
  count = local.self_service ? 1 : 0

  yaml_body = yamlencode({
    apiVersion = "external-secrets.io/v1beta1"
    kind       = "ExternalSecret"
    metadata = {
      name      = var.customer_secret_name
      namespace = var.ekai_namespace
    }
    spec = {
      refreshInterval = "1m"
      secretStoreRef = {
        name = var.cluster_secret_store_name
        kind = "ClusterSecretStore"
      }
      target = {
        # MUST match the ekai-saas chart's secretName (self_service_helm_values
        # sets secretName = var.customer_secret_name below) — this is the K8s
        # Secret name every pod's envFrom actually reads from. Was hardcoded to
        # "ekai-customer-env" before, silently mismatched once
        # customer_secret_name's default changed to "ekai-customer".
        name           = var.customer_secret_name
        creationPolicy = "Owner"
      }
      dataFrom = [{
        extract = {
          key = var.customer_secret_name
        }
      }]
    }
  })

  depends_on = [kubernetes_namespace.ekai_app]
}

# ── Per-service IRSA roles + Kubernetes ServiceAccounts ──────────────────────
# Each application pod authenticates to AWS (Secrets Manager, S3, CloudWatch)
# using a short-lived OIDC token exchanged for an IAM role — no static keys.
module "app_irsa" {
  source = "../app_irsa"

  env                         = var.env
  region                      = var.region
  ekai_namespace              = var.ekai_namespace
  oidc_issuer_url             = var.oidc_issuer
  pipelines                   = local.resolved_pipelines
  self_service                = local.self_service
  shared_service_account_name = var.shared_service_account_name
  customer_secret_name        = var.customer_secret_name
  customer_bucket_arn         = local.self_service ? aws_s3_bucket.ekai_files[0].arn : ""

  depends_on = [kubernetes_namespace.ekai_app, kubectl_manifest.external_secret, kubectl_manifest.external_secret_shared]
}

# ── Service Route53 DNS records ───────────────────────────────────────────────
# for_each is based on local.resolved_pipelines (derived from static variables) —
# always known at plan
# time, no "Invalid count/for_each argument" errors regardless of cluster state.
#
# null_resource.wait_for_alb polls AWS API every 30 s until the shared ALB
# is provisioned by the ALB controller after ArgoCD syncs the ingress manifest.
# data.aws_lb reads the hostname AFTER the wait — records value is "known after
# apply" at plan time (acceptable for resource attributes, only count/for_each
# must be known at plan time).
resource "null_resource" "wait_for_alb" {
  triggers = {
    # Re-run whenever the ArgoCD application changes
    app_depends = module.ekai_CD.argocd_app_name
  }

  provisioner "local-exec" {
    command = <<-EOT
      echo "Waiting for ${local.shared_alb_name} to be provisioned..."
      for i in $(seq 1 24); do
        ALB=$(aws elbv2 describe-load-balancers \
          --region "${var.region}" \
          --query "LoadBalancers[?LoadBalancerName=='${local.shared_alb_name}'].DNSName" \
          --output text 2>/dev/null || echo "")
        if [ -n "$ALB" ] && [ "$ALB" != "None" ]; then
          echo "ALB ready: $ALB"
          exit 0
        fi
        echo "Attempt $i/24 — ALB not ready yet, retrying in 30s..."
        sleep 30
      done
      echo "ALB not found after 12 minutes — Route53 records will be empty"
      exit 1
    EOT
  }

  depends_on = [module.ekai_CD]
}

data "aws_lb" "ekai_shared" {
  name       = local.shared_alb_name
  depends_on = [null_resource.wait_for_alb]
}

resource "aws_route53_record" "services" {
  for_each = {
    for k, v in local.resolved_pipelines : k => v.ingresshost
    if v.ingresshost != ""
  }

  zone_id = local.route53_zone_id
  name    = each.value
  type    = "CNAME"
  ttl     = 300
  records = [data.aws_lb.ekai_shared.dns_name]
}

# cicd_provider = "none" only — the block above is driven by var.pipelines,
# which self-service never populates (there's no CI pipeline to describe),
# so without this, every hostname generated_service_urls/self_service_helm_values
# already bakes into the customer secret and chart Ingress (portal/backend/
# erd.<dns_zone>) would be NXDOMAIN after a successful apply — nothing else
# in this stack creates these records. profile/semantics excluded — those
# services are disabled by default in the ekai-saas chart.
resource "aws_route53_record" "self_service_services" {
  for_each = local.self_service ? toset(["portal", "backend", "erd"]) : toset([])

  zone_id = local.route53_zone_id
  name    = "${each.value}.${var.dns_zone}"
  type    = "CNAME"
  ttl     = 300
  records = [data.aws_lb.ekai_shared.dns_name]
}

# ── ArgoCD application + Route53 DNS records ─────────────────────────────────
module "ekai_CD" {
  source = "../ekai_CD"

  env             = var.env
  ekai_namespace  = var.ekai_namespace
  source_type     = local.self_service ? "helm" : "git"
  CD_branch       = var.CD_branch
  manifest_folder = var.manifest_folder
  github_org      = var.github_org
  github_username = local.github_username
  github_token    = local.github_token

  # source_type = "helm" only
  helm_repo_url      = var.helm_chart_repo_url
  helm_chart_version = var.helm_chart_version
  helm_values        = local.self_service_helm_values

  depends_on = [
    kubectl_manifest.external_secret,
    kubectl_manifest.external_secret_shared,
    module.app_irsa,
  ]
}
