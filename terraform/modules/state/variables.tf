variable "bucket_name" {
  description = "Nombre del bucket S3 (emulado) donde se guarda el estado remoto"
  type        = string
}

variable "environment" {
  description = "Ambiente al que pertenece el estado"
  type        = string
}
