output "kubeconfig" {
  description = "Kubeconfig YAML del clúster"
  value       = data.external.kubeconfig.result.kubeconfig
  sensitive   = true
}

output "host" {
  description = "Endpoint de la API de Kubernetes"
  value       = aws_eks_cluster.this.endpoint
}

output "cluster_ca_certificate" {
  description = "CA del clúster en base64"
  value       = data.external.kubeconfig.result.cluster_ca_certificate
  sensitive   = true
}

output "client_certificate" {
  description = "Certificado de cliente (base64)"
  value       = data.external.kubeconfig.result.client_certificate
  sensitive   = true
}

output "client_key" {
  description = "Clave de cliente (base64)"
  value       = data.external.kubeconfig.result.client_key
  sensitive   = true
}
