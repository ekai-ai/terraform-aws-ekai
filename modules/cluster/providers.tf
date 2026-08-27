# Submodule note: provider "aws" {} and provider "kubernetes" {} configuration
# blocks now live only in the root module's providers.tf (a submodule cannot
# declare a provider configuration block of its own). The kubernetes provider
# used here (by kubernetes_config_map_v1_data.aws_auth and module.rds's
# namespace/job resources) is configured at root pointing at this same
# cluster's endpoint/CA — see ../../providers.tf.
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
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.38"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }
}
