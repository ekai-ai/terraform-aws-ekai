terraform {
  required_providers {
    argocd = {
      source  = "argoproj-labs/argocd"
      version = "7.11.2"
    }
    time = {
      source  = "hashicorp/time"
      version = "~> 0.12"
    }
  }
}
