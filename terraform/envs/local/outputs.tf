output "kubeconfig_path" {
  description = "Archivo kubeconfig local (ignorado por git)"
  value       = local_sensitive_file.kubeconfig.filename
}

output "kubeconfig" {
  description = "Kubeconfig YAML del clúster"
  value       = module.eks.kubeconfig
  sensitive   = true
}

output "argocd_url" {
  description = "Acceso a Argo CD (requiere kubectl port-forward)"
  value       = module.platform.argocd_url
}

output "installed_components" {
  description = "Componentes de plataforma y versión de chart"
  value       = module.platform.installed_components
}
