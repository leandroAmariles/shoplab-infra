resource "helm_release" "argo_cd" {
  name             = "argo-cd"
  namespace        = "argocd"
  create_namespace = true
  repository       = "https://argoproj.github.io/argo-helm"
  chart            = "argo-cd"
  version          = var.chart_versions.argo_cd

  # Interfaz por el ingress local (ingress-nginx, LAB-98). Tras el ingress se sirve HTTP: el TLS queda fuera de alcance.
  values = [yamlencode({
    server  = { ingress = { enabled = true, ingressClassName = "nginx", hostname = var.argocd_host } }
    configs = { params = { "server.insecure" = true } }
  })]

  # Redis usa un repositorio configurable (por defecto el del chart): ecr-public.aws.com responde 429 a descargas
  # anónimas desde los runners de CI. El tag lo sigue fijando el chart.
  set = [{
    name  = "redis.image.repository"
    value = var.argocd_redis_image_repository
  }]

  wait    = true
  timeout = 600

  # Último componente: se instala cuando ingress, secretos, almacenamiento y monitorización ya están listos.
  depends_on = [
    helm_release.ingress_nginx,
    helm_release.local_path_storage,
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
