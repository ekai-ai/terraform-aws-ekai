
# Get OIDC information for the EKS cluster
data "aws_eks_cluster" "eks" {
  name = var.eks_cluster_name
}

data "aws_eks_cluster_auth" "eks" {
  name = var.eks_cluster_name
}

## Fetch OIDC provider URL
#data "aws_iam_openid_connect_provider" "eks_oidc" {
#  url = data.aws_eks_cluster.eks.identity[0].oidc[0].issuer
#}
#data "aws_caller_identity" "current" {}
## IAM Role for Service Account
#resource "aws_iam_role" "service_account_role" {
#  name = "aws_eks_addon-cloudwatch-role"
#
#  assume_role_policy = jsonencode({
#    Version = "2012-10-17",
#    Statement = [{
#      Effect = "Allow",
#      Principal = {
#        Federated = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:oidc-provider/${replace(data.aws_eks_cluster.eks.identity[0].oidc[0].issuer, "https://", "")}"
#      },
#      Action = "sts:AssumeRoleWithWebIdentity",
#      Condition = {
#        StringEquals = {
#          "${replace(data.aws_eks_cluster.eks.identity[0].oidc[0].issuer, "https://", "")}:aud" = "sts.amazonaws.com"
#          "${replace(data.aws_eks_cluster.eks.identity[0].oidc[0].issuer, "https://", "")}:sub" = "system:serviceaccount:${var.cloudwatch_namespace}:cloudwatch-agent-service-account"
#        }
#      }
#    }]
#  })
#}

# Attach the Amazon CloudWatch policy to the service account role
#resource "aws_iam_policy_attachment" "cloudwatch_policy" {
#  name       = "cloudwatch-agent-policy-attachment"
#  roles      = [aws_iam_role.service_account_role.name]
#  policy_arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
#}
#
# Add-on for CloudWatch Observability in EKS
resource "aws_eks_addon" "cloudwatch_addon" {
  cluster_name = var.eks_cluster_name
  addon_name   = "amazon-cloudwatch-observability"
  #addon_version   = "" # Use a supported version, or leave empty for latest.
  #service_account_role_arn = aws_iam_role.service_account_role.arn

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