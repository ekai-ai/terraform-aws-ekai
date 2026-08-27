# ──────────────────────────────────────────────────────────────────────────────
# Root providers (bootstrap + cluster + platform) — required_providers is the
# union of what THESE 3 submodules' trees actually use. Provider
# *configuration* blocks (provider "aws" {}, "kubernetes" {}, "helm" {},
# "kubectl" {}) live here (this directory still configures its own providers,
# same as before — only the backend block moved out, see below) — the
# bootstrap/cluster/platform submodules cannot declare their own provider
# config, only require providers via their own required_providers block (kept
# in each modules/<name>/providers.tf for documentation).
#
# provider "argocd" is intentionally NOT declared here (moved to ../cicd/
# providers.tf instead): nothing under bootstrap/cluster/platform's module
# tree creates an argocd_* resource — only modules/ekai_CD does (verified by
# grep), and that module is only ever called by modules/cicd, which is not
# part of this root anymore. See main.tf's file header for the full reasoning
# (the argocd provider's `password` field can't safely be configured from a
# same-apply resource attribute the way kubernetes/helm/kubectl's `exec`
# block can — that's WHY cicd is split back out into its own apply).
#
# provider "null" is also NOT declared here for the same reason: the only
# null_resource in this codebase (wait_for_alb) lives in modules/cicd/main.tf.
#
# provider "github" is intentionally NOT declared: nothing in this
# distribution's ported module set (under bootstrap/cluster/platform OR cicd)
# actually creates a github_* resource — only modules/github_actions_cicd
# did, and that module is not included here (self-service only — see
# modules/cicd/main.tf's file header).
#
# required_version — the strictest of the 3 original layers' (01-bootstrap
# required ">= 1.9", 02-cluster/03-platform required ">= 1.5"); Terraform
# checks each submodule's own required_version block too, so this mainly
# documents the real minimum up front.
# ──────────────────────────────────────────────────────────────────────────────

terraform {
  required_version = ">= 1.9"

  # No backend block here — this directory is a reusable Terraform module
  # (module "infra" { source = "registry.terraform.io/ekai-ai/ekai/aws" } for
  # registry consumers, or a plain relative `source` for anyone using this
  # repo directly), not a state-holding root config. The actual root config
  # that DOES declare a backend and gets applied is
  # examples/self-deploy/root/ — see that directory's main.tf, and
  # scripts/init-state-backend.sh for how its backend config is generated.
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.38"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.38"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.16"
    }
    kubectl = {
      source  = "gavinbunney/kubectl"
      version = "~> 1.14"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
    time = {
      source  = "hashicorp/time"
      version = "~> 0.12"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }
}

provider "aws" {
  region = var.region
}

# Kubernetes/Helm/kubectl providers — configured from the cluster submodule's
# own outputs. This is a same-apply "provider configured from a resource this
# apply also creates" pattern: Terraform defers actually connecting until the
# first kubernetes/helm/kubectl resource is planned/applied (all of which live
# inside the cluster/platform submodules), by which time the EKS cluster
# already exists. This works specifically because each provider's `exec`
# block is a documented deferred-auth escape hatch — the provider doesn't
# need `host`/`cluster_ca_certificate` to be "known" in the same eager way a
# plain credential field would. This exact pattern was already relied on
# inside the source codebase's own 02-cluster layer (its kubernetes provider
# was configured from module.eks's own output, used by a resource in that
# same layer/state) — this is the same trick, just one level higher now that
# bootstrap/cluster/platform are one state. (The ArgoCD provider does NOT
# have this escape hatch, which is why it's configured in ../cicd/providers.tf
# from a remote_state read instead — see main.tf's file header.)
provider "kubernetes" {
  host                   = module.cluster.cluster_endpoint
  cluster_ca_certificate = base64decode(module.cluster.cluster_ca)
  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    args        = ["eks", "get-token", "--cluster-name", module.cluster.eks_cluster_name, "--region", var.region]
  }
}

provider "helm" {
  kubernetes {
    host                   = module.cluster.cluster_endpoint
    cluster_ca_certificate = base64decode(module.cluster.cluster_ca)
    exec {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "aws"
      args        = ["eks", "get-token", "--cluster-name", module.cluster.eks_cluster_name, "--region", var.region]
    }
  }
}

provider "kubectl" {
  host                   = module.cluster.cluster_endpoint
  cluster_ca_certificate = base64decode(module.cluster.cluster_ca)
  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    args        = ["eks", "get-token", "--cluster-name", module.cluster.eks_cluster_name, "--region", var.region]
  }
  load_config_file = false
}
