# ── Identity lookup ───────────────────────────────────────────────────────────
data "aws_caller_identity" "current" {}

locals {
  clean_oidc = replace(var.oidc_issuer_url, "https://", "")
}

# ── Per-service IRSA role (codebuild/github_actions envs — unchanged) ────────
resource "aws_iam_role" "app" {
  for_each = var.self_service ? {} : var.pipelines

  name = "${var.env}-${each.key}-irsa-${var.region}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Federated = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:oidc-provider/${local.clean_oidc}"
      }
      Action = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "${local.clean_oidc}:sub" = "system:serviceaccount:${var.ekai_namespace}:${each.key}-sa"
          "${local.clean_oidc}:aud" = "sts.amazonaws.com"
        }
      }
    }]
  })

  tags = {
    Name      = "${var.env}-${each.key}-irsa"
    ManagedBy = "Terraform"
    Env       = var.env
    Service   = each.key
  }
}

# ── Per-service IAM inline policy (codebuild/github_actions envs — unchanged)
resource "aws_iam_role_policy" "app" {
  for_each = var.self_service ? {} : var.pipelines

  name = "${var.env}-${each.key}-policy-${var.region}"
  role = aws_iam_role.app[each.key].name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "SecretsManagerAccess"
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue",
          "secretsmanager:DescribeSecret",
        ]
        Resource = "arn:aws:secretsmanager:${var.region}:${data.aws_caller_identity.current.account_id}:secret:${var.env}-${each.key}*"
      },
      {
        Sid    = "S3Access"
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:ListBucket",
        ]
        Resource = [
          "arn:aws:s3:::${var.env}-ekai-*",
          "arn:aws:s3:::${var.env}-ekai-*/*",
        ]
      },
      {
        Sid    = "CloudWatchLogsAccess"
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
        ]
        Resource = "*"
      },
    ]
  })
}

# ── Per-service Kubernetes ServiceAccount (codebuild/github_actions envs) ────
resource "kubernetes_service_account" "app" {
  for_each = var.self_service ? {} : var.pipelines

  metadata {
    name      = "${each.key}-sa"
    namespace = var.ekai_namespace

    annotations = {
      "eks.amazonaws.com/role-arn" = aws_iam_role.app[each.key].arn
    }

    labels = {
      "app.kubernetes.io/managed-by" = "Terraform"
      "app.kubernetes.io/component"  = "irsa"
    }
  }
}

# ── Shared IRSA role (self_service = true — matches the ekai-saas Helm
# chart's one-secret/one-ServiceAccount model instead of one per service) ────
resource "aws_iam_role" "shared" {
  count = var.self_service ? 1 : 0

  name = "${var.env}-shared-irsa-${var.region}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Federated = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:oidc-provider/${local.clean_oidc}"
      }
      Action = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "${local.clean_oidc}:sub" = "system:serviceaccount:${var.ekai_namespace}:${var.shared_service_account_name}"
          "${local.clean_oidc}:aud" = "sts.amazonaws.com"
        }
      }
    }]
  })

  tags = {
    Name      = "${var.env}-shared-irsa"
    ManagedBy = "Terraform"
    Env       = var.env
  }
}

resource "aws_iam_role_policy" "shared" {
  count = var.self_service ? 1 : 0

  name = "${var.env}-shared-policy-${var.region}"
  role = aws_iam_role.shared[0].name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "SecretsManagerAccess"
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue",
          "secretsmanager:DescribeSecret",
        ]
        Resource = "arn:aws:secretsmanager:${var.region}:${data.aws_caller_identity.current.account_id}:secret:${var.customer_secret_name}*"
      },
      {
        Sid    = "S3Access"
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:ListBucket",
        ]
        # The real bucket 04-cicd creates is "ekai-<env>-<account_id>" — not
        # the "<env>-ekai-*" pattern the per-pipeline policy above uses.
        # Copy-pasting that pattern here matched nothing.
        Resource = [
          var.customer_bucket_arn,
          "${var.customer_bucket_arn}/*",
        ]
      },
      {
        Sid    = "CloudWatchLogsAccess"
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
        ]
        Resource = "*"
      },
    ]
  })
}

resource "kubernetes_service_account" "shared" {
  count = var.self_service ? 1 : 0

  metadata {
    name      = var.shared_service_account_name
    namespace = var.ekai_namespace

    annotations = {
      "eks.amazonaws.com/role-arn" = aws_iam_role.shared[0].arn
    }

    labels = {
      "app.kubernetes.io/managed-by" = "Terraform"
      "app.kubernetes.io/component"  = "irsa"
    }
  }
}
