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
    kind = {
      source  = "tehcyx/kind"
      version = "0.13.0"
    }
  }
}
