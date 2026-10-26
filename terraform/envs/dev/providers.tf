# Todo apunta al emulador Floci; las credenciales son ficticias (no hay cuenta de AWS).
provider "aws" {
  region                      = var.region
  access_key                  = "test"
  secret_key                  = "test"
  skip_credentials_validation = true
  skip_requesting_account_id  = true
  skip_metadata_api_check     = true
  s3_use_path_style           = true

  endpoints {
    s3             = var.emulator_endpoint
    iam            = var.emulator_endpoint
    ec2            = var.emulator_endpoint
    eks            = var.emulator_endpoint
    sts            = var.emulator_endpoint
    secretsmanager = var.emulator_endpoint
    ssm            = var.emulator_endpoint
  }
}

# helm y kubernetes se configuran con las salidas del módulo eks (certificado de cliente de k3s).
provider "kubernetes" {
  host                   = module.eks.host
  cluster_ca_certificate = base64decode(module.eks.cluster_ca_certificate)
  client_certificate     = base64decode(module.eks.client_certificate)
  client_key             = base64decode(module.eks.client_key)
}

provider "helm" {
  kubernetes = {
    host                   = module.eks.host
    cluster_ca_certificate = base64decode(module.eks.cluster_ca_certificate)
    client_certificate     = base64decode(module.eks.client_certificate)
    client_key             = base64decode(module.eks.client_key)
  }
}
