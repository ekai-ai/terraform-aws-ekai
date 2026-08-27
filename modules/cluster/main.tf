# ──────────────────────────────────────────────────────────────────────────────
# Layer 02 — Cluster (IAM, EKS, RDS, OIDC provider)
# Reads VPC from the bootstrap submodule (wired by the root module — see
# ../../main.tf — instead of a terraform_remote_state read against
# bootstrap's own state, since this is now one apply/one state).
# ──────────────────────────────────────────────────────────────────────────────

locals {
  eks_cluster_full_name = "${var.eks_cluster_name}-saas-${var.env}"
  secrets_name          = var.secrets_name != "" ? var.secrets_name : "${var.env}-ekai-db-credentials"
  self_service          = var.cicd_provider == "none"
}

data "aws_caller_identity" "current" {}

# ── IAM roles (cluster + node group) ─────────────────────────────────────────
module "iam" {
  source = "../iam"
  env    = var.env
  region = var.region
}

# ── EKS cluster ───────────────────────────────────────────────────────────────
module "eks" {
  source               = "../eks"
  cluster_version      = var.cluster_version
  private_subnet_ids   = var.private_subnet_ids
  env                  = var.env
  eks_cluster_name     = var.eks_cluster_name
  eks_cluster_role_arn = module.iam.eks_cluster_role_arn
  public_access_cidrs  = var.eks_public_access_cidrs
}

# ── Managed node group ────────────────────────────────────────────────────────
module "node_group" {
  source             = "../node_group"
  eks_cluster_name   = module.eks.eks_cluster_name
  NODE_GROUP_ARN     = module.iam.NODE_GROUP_ROLE_ARN
  node_min_size      = var.node_min_size
  mode_max_size      = var.mode_max_size
  node_instance      = var.node_instance
  ami_type           = var.node_ami_type
  node_disk_size     = var.node_disk_size
  private_subnet_ids = var.private_subnet_ids
  depends_on         = [module.eks]
}

# ── aws-auth ConfigMap ────────────────────────────────────────────────────────
# This cluster's authentication_mode is CONFIG_MAP (the aws provider's default
# when access_config isn't set) — Kubernetes RBAC access is driven entirely by
# this ConfigMap, nothing is automatic. Without it: the node group's IAM role
# can't join the cluster (nodes stay NotReady forever), and whichever IAM
# identity is running Terraform gets "Unauthorized" on every kubernetes/helm/
# kubectl resource in this and every later layer (03-platform, 04-cicd, and
# modules/rds's db-init job right below this in the same apply) — exactly the
# failure this fixes. data.aws_caller_identity.current.arn captures whoever's
# actually running `terraform apply` (the self-deploy.sh-created
# ekai-terraform-<env> user, in the self-service flow) instead of hardcoding
# a specific identity.
resource "kubernetes_config_map_v1_data" "aws_auth" {
  force = true

  metadata {
    name      = "aws-auth"
    namespace = "kube-system"
  }

  data = {
    mapRoles = yamlencode([
      {
        rolearn  = module.iam.NODE_GROUP_ROLE_ARN
        username = "system:node:{{EC2PrivateDNSName}}"
        groups   = ["system:bootstrappers", "system:nodes"]
      }
    ])
    # mapUsers (not mapRoles) is correct for self-deploy.sh's flow -- it
    # authenticates as a plain IAM user. Running terraform as an assumed
    # role (SSO, GitHub Actions OIDC, etc.) instead would need the
    # underlying role ARN in mapRoles here, not the STS session ARN this
    # data source returns.
    mapUsers = yamlencode([
      {
        userarn  = data.aws_caller_identity.current.arn
        username = "terraform-deployer"
        groups   = ["system:masters"]
      }
    ])
  }

  depends_on = [module.eks, module.node_group]
}

# ── CloudWatch Observability addon ────────────────────────────────────────────
module "amazon_cloudwatch_addon" {
  source               = "../amazon_cloudwatch_addon"
  region               = var.region
  eks_cluster_name     = module.eks.eks_cluster_name
  cloudwatch_namespace = var.cloudwatch_namespace
  depends_on           = [module.node_group]
}

# ── EBS CSI driver addon — required for any PVC (e.g. ERD's workspace volume)
# to actually provision storage. Needs the OIDC provider registered below, so
# this must come after that resource.
module "ebs_csi_driver" {
  source           = "../ebs_csi_driver"
  env              = var.env
  region           = var.region
  eks_cluster_name = module.eks.eks_cluster_name
  oidc_issuer_url  = module.eks.oidc_issuer
  depends_on       = [aws_iam_openid_connect_provider.eks]
}

# ── RDS (PostgreSQL) + K8s DB-init job ───────────────────────────────────────
module "rds" {
  source                  = "../rds"
  vpc_id                  = var.vpc_id
  vpc_cidr                = var.vpc_cidr
  private_subnet_ids      = var.private_subnet_ids
  db_instance_class       = var.db_instance_class
  engine_version          = var.engine_version
  storage_type            = var.rds_storage_type
  allocated_storage       = var.allocated_storage
  backup_retention_period = var.backup_retention_period
  multi_az                = var.multi_az
  env                     = var.env
  secrets_name            = local.secrets_name
  self_service            = local.self_service
  # kubernetes_config_map_v1_data.aws_auth must exist first -- module.rds's
  # own kubernetes_namespace/kubernetes_job resources are Unauthorized
  # without it (CONFIG_MAP auth mode grants nothing automatically).
  depends_on = [module.node_group, kubernetes_config_map_v1_data.aws_auth]
}

# ── OIDC Provider — registered in IAM for IRSA (ALB controller, ESO, etc.) ───
# EKS creates the issuer endpoint automatically; this resource registers it in
# IAM so aws_iam_role trust policies can use sts:AssumeRoleWithWebIdentity.
data "tls_certificate" "eks_oidc" {
  url        = module.eks.oidc_issuer
  depends_on = [module.eks]
}

resource "aws_iam_openid_connect_provider" "eks" {
  url             = module.eks.oidc_issuer
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.eks_oidc.certificates[0].sha1_fingerprint]

  tags = {
    Name      = "eks-oidc-${local.eks_cluster_full_name}"
    ManagedBy = "Terraform"
    Env       = var.env
  }

  depends_on = [module.eks]
}
