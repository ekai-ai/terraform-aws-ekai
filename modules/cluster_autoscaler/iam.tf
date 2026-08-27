data "aws_caller_identity" "current" {}

locals {
  clean_oidc_issuer_arn = replace(var.cluster_identity_oidc_issuer_arn, "https://", "")

  assume_role_policy = <<-JSON
    {
      "Version": "2012-10-17",
      "Statement": [
        {
          "Effect": "Allow",
          "Action": "sts:AssumeRoleWithWebIdentity",
          "Principal": {
            "Federated": "arn:aws:iam::${data.aws_caller_identity.current.account_id}:oidc-provider/${local.clean_oidc_issuer_arn}"
          },
          "Condition": {
            "StringEquals": {
              "${local.clean_oidc_issuer_arn}:sub": "system:serviceaccount:kube-system:cluster-autoscaler",
              "${local.clean_oidc_issuer_arn}:aud": "sts.amazonaws.com"
            }
          }
        }
      ]
    }
  JSON
}

resource "aws_iam_role" "cluster_autoscaler" {
  count              = var.enabled ? 1 : 0
  name               = "${var.cluster_name}-cluster-autoscaler"
  assume_role_policy = local.assume_role_policy
}

# Read-only actions need no resource scoping (AWS doesn't support
# resource-level permissions for these Describe calls). The two mutating
# actions are scoped to only the ASG(s) tagged for this specific cluster —
# see asg_tags.tf, which is the tag this condition checks for.
resource "aws_iam_policy" "cluster_autoscaler" {
  count       = var.enabled ? 1 : 0
  name        = "${var.cluster_name}-cluster-autoscaler-${var.aws_region}"
  path        = "/"
  description = "Policy for Cluster Autoscaler to scale the self-service node group's ASG"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "autoscaling:DescribeAutoScalingGroups",
          "autoscaling:DescribeAutoScalingInstances",
          "autoscaling:DescribeLaunchConfigurations",
          "autoscaling:DescribeScalingActivities",
          "autoscaling:DescribeTags",
          "ec2:DescribeInstanceTypes",
          "ec2:DescribeLaunchTemplateVersions",
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "autoscaling:SetDesiredCapacity",
          "autoscaling:TerminateInstanceInAutoScalingGroup",
        ]
        Resource = "*"
        Condition = {
          StringEquals = {
            "autoscaling:ResourceTag/k8s.io/cluster-autoscaler/${var.cluster_name}" = "owned"
          }
        }
      },
    ]
  })
}

resource "aws_iam_role_policy_attachment" "cluster_autoscaler" {
  count      = var.enabled ? 1 : 0
  role       = aws_iam_role.cluster_autoscaler[0].name
  policy_arn = aws_iam_policy.cluster_autoscaler[0].arn
}
