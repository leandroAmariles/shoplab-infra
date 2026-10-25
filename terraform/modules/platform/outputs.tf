output "argocd_url" {
  description = "URL de Argo CD tras ejecutar: kubectl -n argocd port-forward svc/argo-cd-argocd-server 8080:80"
  value       = "http://localhost:8080"
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
