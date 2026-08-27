# Submodule note: provider "aws" {}, provider "kubernetes" {}, provider
# "helm" {}, and provider "kubectl" {} configuration blocks now live only in
# the root module's providers.tf (a submodule cannot declare a provider
# configuration block of its own) — see ../../providers.tf. Those blocks
# used to be configured here from a `data "terraform_remote_state" "cluster"`
# read (cluster_endpoint/cluster_ca/eks_cluster_name); root now gets the same
# values directly from module.cluster's outputs.
#
# required_providers is kept here too — harmless, and documents this
# submodule's own provider requirements independent of root.

terraform {
  required_version = ">= 1.5"
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
