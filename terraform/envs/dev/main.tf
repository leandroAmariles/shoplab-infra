# Endpoint de Floci visto desde los pods. En modo floci es la IP del contenedor en la red de compose (los pods
# de k3s no resuelven nombres de contenedor); en kind sí funciona host.docker.internal.
data "external" "floci_ip" {
  count = var.cluster_secrets_endpoint == "" && var.cluster_mode == "floci" ? 1 : 0

  program = ["bash", "${path.module}/../../../scripts/floci-ip.sh"]
}

locals {
  cluster_secrets_endpoint = (
    var.cluster_secrets_endpoint != "" ? var.cluster_secrets_endpoint :
    var.cluster_mode == "floci" ? "http://${data.external.floci_ip[0].result.ip}:4566" :
    "http://host.docker.internal:4566"
  )

  # Application raíz de Argo CD: el manifiesto vive en git (k8s/argocd/root.yaml) y Terraform solo lo crea al arrancar.
  argocd_root = yamldecode(file("${path.module}/../../../k8s/argocd/root.yaml"))
}

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

# Claves de Secrets Manager y SSM bajo /shoplab/<ambiente>/...: las que lee el overlay dev de k8s/ (LAB-80).
module "secrets" {
  source = "../../modules/secrets"

  environment = var.environment
  secrets     = var.secrets
  parameters  = var.parameters
}

module "platform" {
  source = "../../modules/platform"

  chart_versions                = var.chart_versions
  region                        = var.region
  secrets_endpoint              = local.cluster_secrets_endpoint
  argocd_redis_image_repository = var.argocd_redis_image_repository
  argocd_initial_app            = local.argocd_root

  depends_on = [module.eks]
}

# Demostración: un ExternalSecret que copia un secreto de Secrets Manager (Floci) a un Secret del clúster.
resource "helm_release" "demo_external_secret" {
  name             = "demo-external-secret"
  namespace        = "demo"
  create_namespace = true
  chart            = "${path.module}/charts/demo-external-secret"

  values = [yamlencode({
    remoteKey = "/shoplab/${var.environment}/postgres-password"
  })]

  wait    = true
  timeout = 300

  depends_on = [module.platform, module.secrets]
}
