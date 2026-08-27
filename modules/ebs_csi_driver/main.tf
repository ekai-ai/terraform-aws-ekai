# ── IRSA role for the EBS CSI driver's controller ServiceAccount ─────────────
# The addon needs real AWS permissions (CreateVolume/AttachVolume/etc.) to
# provision EBS-backed PersistentVolumes — unlike the CloudWatch addon, this
# one doesn't work off node IAM permissions alone.
data "aws_caller_identity" "current" {}

locals {
  clean_oidc_issuer = replace(var.oidc_issuer_url, "https://", "")
}

resource "aws_iam_role" "ebs_csi" {
  name = "${var.env}-ebs-csi-driver-${var.region}"

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
          "${local.clean_oidc_issuer}:sub" = "system:serviceaccount:kube-system:ebs-csi-controller-sa"
          "${local.clean_oidc_issuer}:aud" = "sts.amazonaws.com"
        }
      }
    }]
  })

  tags = { Name = "${var.env}-ebs-csi-driver", ManagedBy = "Terraform", Env = var.env }
}

resource "aws_iam_role_policy_attachment" "ebs_csi" {
  role       = aws_iam_role.ebs_csi.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
}

# ── EKS addon ──────────────────────────────────────────────────────────────────
resource "aws_eks_addon" "ebs_csi" {
  cluster_name             = var.eks_cluster_name
  addon_name               = "aws-ebs-csi-driver"
  addon_version            = var.addon_version != "" ? var.addon_version : null
  service_account_role_arn = aws_iam_role.ebs_csi.arn
  # OVERWRITE on create too — EKS often pre-suggests/auto-installs this addon,
  # so a first apply on a cluster that already has it errors
  # ResourceInUseException without this (create-time conflicts default to
  # "NONE", update-time already handled below).
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"

  tags = {
    Name    = "ebs-csi-driver-addon-${var.eks_cluster_name}"
    managed = "terraform"
  }

  depends_on = [aws_iam_role_policy_attachment.ebs_csi]
}
