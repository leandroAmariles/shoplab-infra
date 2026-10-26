output "argocd_url" {
  description = "URL de Argo CD por el ingress, tras ejecutar: kubectl -n ingress-nginx port-forward svc/ingress-nginx-controller 8080:80"
  value       = "http://${var.argocd_host}:8080"
}

output "installed_components" {
  description = "Componente => versión del chart instalada"
  value = {
    ingress-nginx         = helm_release.ingress_nginx.version
    external-secrets      = helm_release.external_secrets.version
    kube-prometheus-stack = helm_release.kube_prometheus_stack.version
    argo-cd               = helm_release.argo_cd.version
  }
}
