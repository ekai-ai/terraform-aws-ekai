resource "aws_eks_cluster" "eks" {
  name     = "${var.eks_cluster_name}-saas-${var.env}"
  role_arn = var.eks_cluster_role_arn
  version  = var.cluster_version

  vpc_config {
    endpoint_private_access = true
    endpoint_public_access  = true
    public_access_cidrs     = var.public_access_cidrs
    subnet_ids              = var.private_subnet_ids
  }

  enabled_cluster_log_types = [
    "api",
    "audit",
    "authenticator",
    "controllerManager",
    "scheduler",
  ]

  tags = {
    Name      = "${var.eks_cluster_name}-saas-${var.env}"
    ManagedBy = "Terraform"
    Env       = var.env
  }
}
