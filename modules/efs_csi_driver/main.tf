# ── IRSA role for the EFS CSI driver's controller ServiceAccount ─────────────
# Same shape as modules/ebs_csi_driver -- one cluster-wide role covering all
# EFS mount/write operations the driver performs on behalf of any pod. No
# per-workload IAM scoping: ERD workspace access is controlled by the
# security group (NFS from the VPC only) and the access point's POSIX
# permissions instead, same as a normal shared filesystem.
data "aws_caller_identity" "current" {}

locals {
  clean_oidc_issuer = replace(var.oidc_issuer_url, "https://", "")
}

resource "aws_iam_role" "efs_csi" {
  name = "${var.env}-efs-csi-driver-${var.region}"

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
          "${local.clean_oidc_issuer}:sub" = "system:serviceaccount:kube-system:efs-csi-controller-sa"
          "${local.clean_oidc_issuer}:aud" = "sts.amazonaws.com"
        }
      }
    }]
  })

  tags = { Name = "${var.env}-efs-csi-driver", ManagedBy = "Terraform", Env = var.env }
}

resource "aws_iam_role_policy_attachment" "efs_csi" {
  role       = aws_iam_role.efs_csi.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEFSCSIDriverPolicy"
}

# ── EKS addon ──────────────────────────────────────────────────────────────────
resource "aws_eks_addon" "efs_csi" {
  cluster_name                = var.eks_cluster_name
  addon_name                  = "aws-efs-csi-driver"
  addon_version               = var.addon_version != "" ? var.addon_version : null
  service_account_role_arn    = aws_iam_role.efs_csi.arn
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"

  tags = {
    Name    = "efs-csi-driver-addon-${var.eks_cluster_name}"
    managed = "terraform"
  }

  depends_on = [aws_iam_role_policy_attachment.efs_csi]
}
