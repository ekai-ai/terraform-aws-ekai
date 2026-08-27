# Submodule note: provider "aws" {}, provider "kubernetes" {}, provider
# "helm" {}, provider "kubectl" {}, and provider "argocd" {} configuration
# blocks now live only in the root module's providers.tf (a submodule cannot
# declare a provider configuration block of its own) — see ../../providers.tf.
# Those blocks used to be configured here from `data "terraform_remote_state"`
# reads against the cluster/platform states; root now gets the same values
# directly from module.cluster's / module.platform's outputs.
#
# provider "github" is NOT declared here (or at root): nothing in this
# distribution's ported module set (module.ekai_CD, module.app_irsa, ...)
# actually uses a github_* resource — modules/github_actions_cicd is the only
# thing in the source codebase that did, and it is intentionally not included
# (see main.tf's file header). github_org/github_username/github_token are
# still plumbed through as plain string variables (module.ekai_CD's git
# source_type branch takes them as repository-credential values, not via the
# github provider), so removing the provider entirely is safe.
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
    argocd = {
      source  = "argoproj-labs/argocd"
      version = "~> 7.11"
    }
    null = {
      source  = "hashicorp/null"
      version = "~> 3.2"
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
