resource "helm_release" "cluster_autoscaler" {
  count      = var.enabled ? 1 : 0
  name       = "cluster-autoscaler"
  chart      = "cluster-autoscaler"
  repository = "https://kubernetes.github.io/autoscaler"
  version    = var.helm_chart_version
  namespace  = "kube-system"
  timeout    = 300

  values = [
    yamlencode({
      autoDiscovery = {
        clusterName = var.cluster_name
      }
      awsRegion = var.aws_region

      rbac = {
        serviceAccount = {
          create = true
          name   = "cluster-autoscaler"
          annotations = {
            "eks.amazonaws.com/role-arn" = aws_iam_role.cluster_autoscaler[0].arn
          }
        }
      }

      extraArgs = {
        # Every node here also runs DaemonSets (aws-node, kube-proxy, fluent-bit,
        # cloudwatch-agent, guardduty-agent) -- without this, CA treats those as
        # "system pods" and refuses to ever scale a node back down to 0.
        skip-nodes-with-system-pods = "false"
        balance-similar-node-groups = "true"
      }
    })
  ]

  depends_on = [
    aws_iam_role_policy_attachment.cluster_autoscaler,
    aws_autoscaling_group_tag.cluster_autoscaler_enabled,
    aws_autoscaling_group_tag.cluster_autoscaler_cluster_name,
  ]
}
