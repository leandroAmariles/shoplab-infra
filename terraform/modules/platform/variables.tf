variable "chart_versions" {
  description = "Versión exacta de cada chart de la plataforma"
  type = object({
    ingress_nginx         = string
    external_secrets      = string
    kube_prometheus_stack = string
    argo_cd               = string
  })

  validation {
    condition = alltrue([
      for v in values(var.chart_versions) : can(regex("^[0-9]+\\.[0-9]+\\.[0-9]+$", v))
    ])
    error_message = "Cada versión de chart debe ser exacta (X.Y.Z): sin latest ni rangos"
  }
}

variable "secrets_endpoint" {
  description = "Endpoint de Secrets Manager (Floci) visto desde los pods del clúster"
  type        = string
  default     = "http://host.docker.internal:4566"
}

variable "region" {
  description = "Región ficticia del emulador"
  type        = string
  default     = "us-east-1"
}

variable "argocd_initial_app" {
  description = "Application inicial que Argo CD sincroniza (repositorio público)"
  type = object({
    name            = string
    repo_url        = string
    path            = string
    target_revision = string
    namespace       = string
  })
  default = {
    name            = "guestbook"
    repo_url        = "https://github.com/argoproj/argocd-example-apps.git"
    path            = "guestbook"
    target_revision = "HEAD"
    namespace       = "guestbook"
  }
}
