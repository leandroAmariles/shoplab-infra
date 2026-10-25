variable "cluster_name" {
  description = "Nombre del clúster EKS emulado"
  type        = string
}

variable "kubernetes_version" {
  description = "Versión de Kubernetes solicitada al emulador"
  type        = string
  default     = "1.35"
}

variable "cluster_mode" {
  description = "floci (EKS emulado sobre k3s, por defecto) o kind (respaldo)"
  type        = string
  default     = "floci"

  validation {
    condition     = contains(["floci", "kind"], var.cluster_mode)
    error_message = "cluster_mode debe ser 'floci' o 'kind'"
  }
}
