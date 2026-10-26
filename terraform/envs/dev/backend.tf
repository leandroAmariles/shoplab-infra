# Configuración parcial: la clave del estado por ambiente se pasa con -backend-config (scripts/init-env.sh).
terraform {
  backend "s3" {
    bucket                      = "shoplab-tfstate-dev"
    region                      = "us-east-1"
    access_key                  = "test"
    secret_key                  = "test"
    use_lockfile                = true
    use_path_style              = true
    skip_credentials_validation = true
    skip_requesting_account_id  = true
    skip_metadata_api_check     = true
    skip_region_validation      = true

    endpoints = {
      s3 = "http://localhost:4566"
    }
  }
}
