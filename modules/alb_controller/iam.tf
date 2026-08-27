resource "aws_iam_policy" "kubernetes_alb_controller" {
  count       = var.enabled ? 1 : 0
  name        = "${var.cluster_name}-alb-controller-${var.aws_region}"
  path        = "/"
  description = "Policy for load balancer controller service"

  policy = file("${path.module}/alb_controller_iam_policy.json")
}

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
              "${local.clean_oidc_issuer_arn}:sub": "system:serviceaccount:kube-system:aws-load-balancer-controller",
              "${local.clean_oidc_issuer_arn}:aud": "sts.amazonaws.com"
            }
          }
        }
      ]
    }
  JSON
}




resource "aws_iam_role" "kubernetes_alb_controller" {
  count              = var.enabled ? 1 : 0
  name               = "${var.cluster_name}-alb-controller"
  assume_role_policy = local.assume_role_policy
}

resource "aws_iam_role_policy_attachment" "kubernetes_alb_controller" {
  count      = var.enabled ? 1 : 0
  role       = aws_iam_role.kubernetes_alb_controller[0].name
  policy_arn = aws_iam_policy.kubernetes_alb_controller[0].arn
}