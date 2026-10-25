resource "helm_release" "external_secrets" {
  name             = "external-secrets"
  namespace        = "external-secrets"
  create_namespace = true
  repository       = "https://charts.external-secrets.io"
  chart            = "external-secrets"
  version          = var.chart_versions.external_secrets

  # El proveedor AWS de ESO acepta endpoints propios por variable de entorno: así apunta a Floci.
  values = [yamlencode({
    extraEnv = [
      { name = "AWS_SECRETSMANAGER_ENDPOINT", value = var.secrets_endpoint },
      { name = "AWS_SSM_ENDPOINT", value = var.secrets_endpoint },
      { name = "AWS_STS_ENDPOINT", value = var.secrets_endpoint },
    ]
  })]

  wait    = true
  timeout = 600

  depends_on = [helm_release.ingress_nginx]
}

# Credenciales ficticias del emulador (no son un secreto real).
resource "kubernetes_secret_v1" "emulator_credentials" {
  metadata {
    name      = "emulator-aws-credentials"
    namespace = "external-secrets"
  }

  data = {
    access-key = "test"
    secret-key = "test"
  }

  depends_on = [helm_release.external_secrets]
}

# Chart local: evita kubernetes_manifest, que exige que el CRD ya exista durante el plan.
resource "helm_release" "secret_store" {
  name      = "secret-store"
  namespace = "external-secrets"
  chart     = "${path.module}/charts/secret-store"

  values = [yamlencode({
    region      = var.region
    credentials = kubernetes_secret_v1.emulator_credentials.metadata[0].name
  })]

  wait    = true
  timeout = 300
}
