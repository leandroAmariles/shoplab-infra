variable "environment" {
  description = "Nombre del ambiente"
  type        = string
  default     = "local"
}

variable "region" {
  description = "Región ficticia del emulador"
  type        = string
  default     = "us-east-1"
}

variable "emulator_endpoint" {
  description = "Endpoint de Floci visto desde el host"
  type        = string
  default     = "http://localhost:4566"
}

variable "cluster_secrets_endpoint" {
  description = "Endpoint de Floci visto desde los pods; vacío = se calcula según cluster_mode"
  type        = string
  default     = ""
}

variable "cluster_mode" {
  description = "floci (EKS emulado, por defecto) o kind (respaldo)"
  type        = string
  default     = "floci"
}

variable "chart_versions" {
  description = "Versión exacta de cada chart de la plataforma"
  type = object({
    ingress_nginx         = string
    external_secrets      = string
    kube_prometheus_stack = string
    argo_cd               = string
  })
  default = {
    ingress_nginx         = "4.15.1"
    external_secrets      = "2.14.0"
    kube_prometheus_stack = "92.13.1"
    argo_cd               = "10.11.1"
  }
}

variable "argocd_redis_image_repository" {
  description = "Repositorio de la imagen de Redis de Argo CD (espejo si ecr-public.aws.com responde 429); sin tag"
  type        = string
  default     = "ecr-public.aws.com/docker/library/redis"
}

variable "secrets" {
  description = "Nombre => valor de los secretos de la app; se proporciona fuera de git (secrets.auto.tfvars o TF_VAR_secrets)"
  type        = map(string)
  sensitive   = true
}

variable "parameters" {
  description = "Nombre => valor de parámetros no sensibles (SSM)"
  type        = map(string)
  default     = {}
}
