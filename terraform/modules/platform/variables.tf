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

variable "argocd_redis_image_repository" {
  description = "Repositorio de la imagen de Redis de Argo CD; el tag lo fija el chart. Permite usar un espejo cuando ecr-public.aws.com limita las descargas anónimas (429)"
  type        = string
  default     = "ecr-public.aws.com/docker/library/redis"

  validation {
    condition     = !strcontains(var.argocd_redis_image_repository, ":")
    error_message = "Indica solo el repositorio, sin tag: el tag lo fija el chart"
  }
}

variable "argocd_host" {
  description = "Host del ingress de Argo CD; *.localtest.me resuelve a 127.0.0.1 sin tocar el archivo hosts"
  type        = string
  default     = "argocd.localtest.me"

  validation {
    condition     = can(regex("^[a-z0-9-]+(\\.[a-z0-9-]+)*\\.localtest\\.me$", var.argocd_host))
    error_message = "argocd_host debe ser un nombre bajo localtest.me (nunca un dominio de producción)"
  }
}

variable "argocd_initial_app" {
  description = "Manifiesto completo de la Application raíz que Argo CD sincroniza (k8s/argocd/root.yaml decodificado); sin valor por defecto"
  type        = any

  validation {
    condition     = try(var.argocd_initial_app.kind == "Application", false)
    error_message = "argocd_initial_app debe ser el manifiesto de una Application de Argo CD (kind: Application)"
  }

  validation {
    condition     = try(!strcontains(var.argocd_initial_app.spec.source.repoURL, "CAMBIA-ESTE-OWNER"), false)
    error_message = "El repoURL de la Application raíz no puede ser el valor de plantilla CAMBIA-ESTE-OWNER"
  }

  validation {
    condition     = try(var.argocd_initial_app.spec.source.targetRevision == "main", false)
    error_message = "La Application raíz debe seguir targetRevision: main"
  }
}
