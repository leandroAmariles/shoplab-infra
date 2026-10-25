# Backend local a propósito: el bucket remoto aún no existe cuando se aplica esta raíz.
module "state" {
  source = "../../../modules/state"

  bucket_name = "shoplab-tfstate-${var.environment}"
  environment = var.environment
}
