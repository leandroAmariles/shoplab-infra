module "eks" {
  source = "../../modules/eks"

  cluster_name = "shoplab-${var.environment}"
  cluster_mode = var.cluster_mode
}

# Archivo local (ignorado por git) para usar kubectl contra el clúster.
resource "local_sensitive_file" "kubeconfig" {
  filename        = "${path.module}/kubeconfig.yaml"
  content         = module.eks.kubeconfig
  file_permission = "0600"
}

module "platform" {
  source = "../../modules/platform"

  chart_versions   = var.chart_versions
  region           = var.region
  secrets_endpoint = var.cluster_secrets_endpoint

  depends_on = [module.eks]
}
