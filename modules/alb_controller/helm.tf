resource "helm_release" "alb_controller" {
  count      = var.enabled ? 1 : 0
  name       = var.helm_chart_name
  chart      = var.helm_chart_release_name
  repository = var.helm_chart_repo
  version    = var.helm_chart_version
  namespace  = "kube-system"
  timeout    = 600

  values = [
    yamlencode({
      clusterName = var.cluster_name
      region      = var.aws_region

      rbac = {
        create = true
      }

      serviceAccount = {
        create = true
        name   = "aws-load-balancer-controller"
        annotations = {
          "eks.amazonaws.com/role-arn" = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/${aws_iam_role.kubernetes_alb_controller[0].name}"
        }
      }

      enableServiceMutatorWebhook = false
    }),
    yamlencode(var.settings)
  ]

  depends_on = [aws_iam_role_policy_attachment.kubernetes_alb_controller]
}
