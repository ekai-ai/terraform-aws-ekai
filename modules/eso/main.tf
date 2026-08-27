# ── IRSA role for ESO ServiceAccount ─────────────────────────────────────────
data "aws_caller_identity" "current" {}

locals {
  clean_oidc_issuer = replace(var.oidc_issuer_url, "https://", "")
}

resource "aws_iam_role" "eso" {
  name = "${var.env}-eso-role-${var.region}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Federated = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:oidc-provider/${local.clean_oidc_issuer}"
      }
      Action = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "${local.clean_oidc_issuer}:sub" = "system:serviceaccount:external-secrets:external-secrets"
          "${local.clean_oidc_issuer}:aud" = "sts.amazonaws.com"
        }
      }
    }]
  })

  tags = { Name = "${var.env}-eso-role", ManagedBy = "Terraform", Env = var.env }
}

resource "aws_iam_role_policy" "eso" {
  name = "${var.env}-eso-secretsmanager-${var.region}"
  role = aws_iam_role.eso.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "secretsmanager:GetSecretValue",
        "secretsmanager:DescribeSecret",
      ]
      # Scoped to this env's secrets — mirrors Azure ESO's Key Vault scope —
      # plus the self-service customer secret, which doesn't follow the
      # "<env>-*" convention (e.g. "ekai-customer", no env prefix at all).
      Resource = compact([
        "arn:aws:secretsmanager:${var.region}:${data.aws_caller_identity.current.account_id}:secret:${var.env}-*",
        var.customer_secret_name != "" ? "arn:aws:secretsmanager:${var.region}:${data.aws_caller_identity.current.account_id}:secret:${var.customer_secret_name}-*" : "",
      ])
    }]
  })
}

# ── ESO namespace ─────────────────────────────────────────────────────────────
resource "kubernetes_namespace" "eso" {
  metadata {
    name = "external-secrets"
  }
}

# ── ESO Helm release ──────────────────────────────────────────────────────────
# ServiceAccount is annotated with the IRSA role ARN so pods token-exchange
# against AWS STS and get scoped Secrets Manager read access.
resource "helm_release" "eso" {
  name       = "external-secrets"
  namespace  = kubernetes_namespace.eso.metadata[0].name
  repository = "https://charts.external-secrets.io"
  chart      = "external-secrets"
  version    = var.chart_version

  values = [yamlencode({
    installCRDs = true

    serviceAccount = {
      create = true
      name   = "external-secrets"
      annotations = {
        "eks.amazonaws.com/role-arn" = aws_iam_role.eso.arn
      }
    }
  })]

  depends_on = [kubernetes_namespace.eso]
}

# ── ClusterSecretStore — points at AWS Secrets Manager ───────────────────────
# Cluster-scoped so any namespace can reference it via ExternalSecret without
# per-namespace wiring — mirrors the Azure ClusterSecretStore pattern.
resource "kubectl_manifest" "cluster_secret_store" {
  yaml_body = yamlencode({
    apiVersion = "external-secrets.io/v1beta1"
    kind       = "ClusterSecretStore"
    metadata = {
      name = "aws-secrets-manager"
    }
    spec = {
      provider = {
        aws = {
          service = "SecretsManager"
          region  = var.region
          auth = {
            jwt = {
              serviceAccountRef = {
                name      = "external-secrets"
                namespace = "external-secrets"
              }
            }
          }
        }
      }
    }
  })

  depends_on = [helm_release.eso]
}
