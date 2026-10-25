variable "environment" {
  description = "Ambiente; forma el prefijo /shoplab/<ambiente>/ de los nombres"
  type        = string
}

variable "required_secrets" {
  description = "Nombres de secretos que deben recibir valor"
  type        = list(string)
  default     = ["postgres-password", "llm-api-key"]
}

variable "secrets" {
  description = "Nombre => valor de los secretos (siempre desde fuera del repositorio)"
  type        = map(string)
  sensitive   = true

  validation {
    condition = alltrue([
      for name in var.required_secrets : trimspace(lookup(var.secrets, name, "")) != ""
    ])
    error_message = "Faltan valores de secretos requeridos. Defínelos en secrets.auto.tfvars (copia secrets.auto.tfvars.example) o con TF_VAR_secrets."
  }
}

variable "parameters" {
  description = "Nombre => valor de parámetros no sensibles (SSM)"
  type        = map(string)
  default     = {}
}
