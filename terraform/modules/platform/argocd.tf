resource "helm_release" "argo_cd" {
  name             = "argo-cd"
  namespace        = "argocd"
  create_namespace = true
  repository       = "https://argoproj.github.io/argo-helm"
  chart            = "argo-cd"
  version          = var.chart_versions.argo_cd

  wait    = true
  timeout = 600

  # Último componente: se instala cuando ingress, secretos y monitorización ya están listos.
  depends_on = [
    helm_release.ingress_nginx,
    helm_release.secret_store,
    helm_release.kube_prometheus_stack,
  ]
}

resource "helm_release" "argocd_initial_app" {
  name      = "argocd-initial-app"
  namespace = "argocd"
  chart     = "${path.module}/charts/argocd-application"

  values = [yamlencode({
    application = var.argocd_initial_app
  })]

  wait    = true
  timeout = 300

  depends_on = [helm_release.argo_cd]
}
