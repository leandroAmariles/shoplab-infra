resource "helm_release" "argo_cd" {
  name             = "argo-cd"
  namespace        = "argocd"
  create_namespace = true
  repository       = "https://argoproj.github.io/argo-helm"
  chart            = "argo-cd"
  version          = var.chart_versions.argo_cd

  # Interfaz por el ingress local (ingress-nginx, LAB-98). Tras el ingress se sirve HTTP: el TLS queda fuera de alcance.
  values = [yamlencode({
    server = { ingress = { enabled = true, ingressClassName = "nginx", hostname = var.argocd_host } }
    configs = {
      params = { "server.insecure" = true }
      cm = {
        # Argo CD excluye por defecto Endpoints y EndpointSlice, y con eso nunca aplicó los EndpointSlice del overlay dev
        # (ollama-host y postgres-host, que dirigen los Service al Docker del host): el backend no encontraba Postgres.
        # Es el valor por defecto del chart (argo-cd 10.x) sin EndpointSlice; Endpoints sigue excluido.
        "resource.exclusions" = <<-EOT
          ### Network resources created by the Kubernetes control plane and excluded to reduce the number of watched events and UI clutter
          - apiGroups:
            - ''
            kinds:
            - Endpoints
          ### Internal Kubernetes resources excluded reduce the number of watched events
          - apiGroups:
            - coordination.k8s.io
            kinds:
            - Lease
          ### Internal Kubernetes Authz/Authn resources excluded reduce the number of watched events
          - apiGroups:
            - authentication.k8s.io
            - authorization.k8s.io
            kinds:
            - SelfSubjectReview
            - TokenReview
            - LocalSubjectAccessReview
            - SelfSubjectAccessReview
            - SelfSubjectRulesReview
            - SubjectAccessReview
          ### Intermediate Certificate Request excluded reduce the number of watched events
          - apiGroups:
            - certificates.k8s.io
            kinds:
            - CertificateSigningRequest
          - apiGroups:
            - cert-manager.io
            kinds:
            - CertificateRequest
          ### Cilium internal resources excluded reduce the number of watched events and UI Clutter
          - apiGroups:
            - cilium.io
            kinds:
            - CiliumIdentity
            - CiliumEndpoint
            - CiliumEndpointSlice
          ### Kyverno intermediate and reporting resources excluded reduce the number of watched events and improve performance
          - apiGroups:
            - kyverno.io
            - reports.kyverno.io
            - wgpolicyk8s.io
            kinds:
            - PolicyReport
            - ClusterPolicyReport
            - EphemeralReport
            - ClusterEphemeralReport
            - AdmissionReport
            - ClusterAdmissionReport
            - BackgroundScanReport
            - ClusterBackgroundScanReport
            - UpdateRequest
        EOT
      }
      # Contraseña fija del laboratorio local (admin): evita leer argocd-initial-admin-secret tras cada `make up`.
      secret = {
        argocdServerAdminPassword      = var.argocd_admin_password_hash
        argocdServerAdminPasswordMtime = "2026-10-27T00:00:00Z"
      }
    }
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
