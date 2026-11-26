# Add-on for CloudWatch Observability in EKS
resource "aws_eks_addon" "cloudwatch_addon" {
  cluster_name = var.eks_cluster_name
  addon_name   = "amazon-cloudwatch-observability"
  #addon_version   = "" # Use a supported version, or leave empty for latest.

  # This addon's own default is applicationSignals.enabled = true, which
  # mutating-webhook-injects OpenTelemetry sidecars into every pod in every
  # namespace AND overrides the main container's resource requests to a fixed
  # 1 CPU / 2Gi -- regardless of what the workload's own chart/manifest asked
  # for. On a lean self-service cluster that alone made normal-sized pods
  # (neo4j, redis, ...) unschedulable ("Insufficient cpu"). Keep basic
  # container log/metric collection, opt out of auto-instrumentation.
  configuration_values = jsonencode({
    applicationSignals = { enabled = false }
  })

  tags = {
    Name    = "cloudwatch-observability-addon-${var.eks_cluster_name}"
    managed = "terraform"
  }
}