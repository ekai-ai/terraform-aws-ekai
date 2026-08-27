# ──────────────────────────────────────────────────────────────────────────────
# cicd providers — required_providers is the subset of the union that THIS
# config's own resources + module.cicd's tree actually use (verified by
# grepping modules/cicd, modules/ekai_CD, modules/app_irsa):
#   aws, kubernetes, kubectl, argocd, random, time, null
# helm is deliberately NOT included: nothing under module.cicd creates a
# helm_release — the `dynamic "helm" {}` block inside modules/ekai_CD's
# argocd_application resource is a nested block of the ARGOCD provider's own
# resource schema (mirrors the ArgoCD Application CRD's spec.source.helm
# field), not a use of the separate "helm" (terraform-provider-helm) provider.
# github is deliberately NOT included, same reasoning as ../providers.tf.
#
# provider "argocd" is THE reason this is a separate apply/state from
# ../ (bootstrap+cluster+platform) — see ../main.tf's file header. Its
# `password` is read from `data.terraform_remote_state.combined.outputs.
# argocd_admin_password_plaintext`: a value from an ALREADY-COMPLETED separate
# apply, which Terraform can treat as known before this apply even starts —
# unlike a same-apply managed resource's computed attribute, which it cannot.
# This is exactly how the original 04-cicd/providers.tf read
# `data.terraform_remote_state.platform.outputs.argocd_admin_password_plaintext`
# (via a local computed in main.tf) against a real, separate 03-platform
# state; only the remote_state key it points at has changed.
# ──────────────────────────────────────────────────────────────────────────────

terraform {
  required_version = ">= 1.5"

  # Partial backend config — provide per-environment via -backend-config flag.
  # Example:
  #   terraform init -backend-config=env/backend-<env>-cicd.tfbackend
  #
  # Second of the 2 states in this repo — see scripts/init-state-backend.sh.
  backend "s3" {}

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.38"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.38"
    }
    kubectl = {
      source  = "gavinbunney/kubectl"
      version = "~> 1.14"
    }
    argocd = {
      source  = "argoproj-labs/argocd"
      version = "~> 7.11"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
    time = {
      source  = "hashicorp/time"
      version = "~> 0.12"
    }
    null = {
      source  = "hashicorp/null"
      version = "~> 3.2"
    }
  }
}

provider "aws" {
  region = var.region
}

locals {
  cluster_endpoint = data.terraform_remote_state.combined.outputs.cluster_endpoint
  cluster_ca       = data.terraform_remote_state.combined.outputs.cluster_ca
  eks_cluster_name = data.terraform_remote_state.combined.outputs.eks_cluster_name

  argocd_host           = coalesce(var.argocd_ingress_host, "argocd.${var.dns_zone}")
  argocd_admin_password = data.terraform_remote_state.combined.outputs.argocd_admin_password_plaintext
}

provider "kubernetes" {
  host                   = local.cluster_endpoint
  cluster_ca_certificate = base64decode(local.cluster_ca)
  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    args        = ["eks", "get-token", "--cluster-name", local.eks_cluster_name, "--region", var.region]
  }
}

provider "kubectl" {
  host                   = local.cluster_endpoint
  cluster_ca_certificate = base64decode(local.cluster_ca)
  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    args        = ["eks", "get-token", "--cluster-name", local.eks_cluster_name, "--region", var.region]
  }
  load_config_file = false
}

# ArgoCD provider — direct URL with grpc_web=true.
# Pure gRPC (HTTP/2) does not traverse HTTP/1.1 ALB proxies -> 464 error.
# grpc_web uses gRPC-Web which is HTTP/1.1 compatible and works through ALB.
#
# SAFE here (unlike a same-apply module.platform.argocd_admin_password_plaintext
# reference would be) because local.argocd_admin_password comes from
# data.terraform_remote_state.combined — a value Terraform already knows
# before this apply starts, read from a state file the ../ apply already
# finished writing.
provider "argocd" {
  server_addr = "${local.argocd_host}:443"
  username    = "admin"
  password    = local.argocd_admin_password
  insecure    = false
  grpc_web    = true
}
