variable "environment" {
  description = "Ambiente cuyo estado se prepara"
  type        = string
  default     = "dev"
}

variable "region" {
  description = "Región ficticia del emulador"
  type        = string
  default     = "us-east-1"
}

variable "emulator_endpoint" {
  description = "Endpoint de Floci"
  type        = string
  default     = "http://localhost:4566"
}
