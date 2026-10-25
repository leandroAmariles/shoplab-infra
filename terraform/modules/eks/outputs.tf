output "kubeconfig" {
  description = "Kubeconfig YAML del clúster"
  value       = local.floci ? data.external.kubeconfig[0].result.kubeconfig : kind_cluster.this[0].kubeconfig
  sensitive   = true
}

output "host" {
  description = "Endpoint de la API de Kubernetes"
  value       = local.floci ? aws_eks_cluster.this[0].endpoint : kind_cluster.this[0].endpoint
}

output "cluster_ca_certificate" {
  description = "CA del clúster en base64"
  value = (
    local.floci ? data.external.kubeconfig[0].result.cluster_ca_certificate :
    base64encode(kind_cluster.this[0].cluster_ca_certificate)
  )
  sensitive = true
}

output "client_certificate" {
  description = "Certificado de cliente (base64)"
  value = (
    local.floci ? data.external.kubeconfig[0].result.client_certificate :
    base64encode(kind_cluster.this[0].client_certificate)
  )
  sensitive = true
}

output "client_key" {
  description = "Clave de cliente (base64)"
  value = (
    local.floci ? data.external.kubeconfig[0].result.client_key :
    base64encode(kind_cluster.this[0].client_key)
  )
  sensitive = true
}
