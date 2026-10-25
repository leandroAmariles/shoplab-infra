output "secret_names" {
  description = "Nombres de los secretos creados en Secrets Manager"
  value       = [for secret in aws_secretsmanager_secret.this : secret.name]
}

output "parameter_names" {
  description = "Rutas de los parámetros creados en SSM"
  value       = [for parameter in aws_ssm_parameter.this : parameter.name]
}
