terraform {
  required_version = "~> 1.15.8"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "6.70.0"
    }
    external = {
      source  = "hashicorp/external"
      version = "2.4.2"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "3.3.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "3.4.0"
    }
    local = {
      source  = "hashicorp/local"
      version = "2.9.1"
    }
  }
}
