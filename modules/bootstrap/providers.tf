# Layer 01 (bootstrap) only manages Route53 and ACM.
# No EKS / Kubernetes providers needed — cluster does not exist yet.
#
# Submodule note: provider "aws" {} configuration now lives only in the root
# module's providers.tf (a submodule cannot declare a provider configuration
# block of its own). required_providers is kept here too — harmless, and
# documents this submodule's own provider requirements independent of root.

terraform {
  required_version = ">= 1.9"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}
