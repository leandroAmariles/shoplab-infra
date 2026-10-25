locals {
  prefix = "/shoplab/${var.environment}"
}

# for_each no admite claves marcadas como sensibles: los nombres no lo son, los valores sí.
resource "aws_secretsmanager_secret" "this" {
  for_each = toset(nonsensitive(keys(var.secrets)))

  name                    = "${local.prefix}/${each.key}"
  recovery_window_in_days = 0
}

resource "aws_secretsmanager_secret_version" "this" {
  for_each = aws_secretsmanager_secret.this

  secret_id     = each.value.id
  secret_string = var.secrets[each.key]
}

resource "aws_ssm_parameter" "this" {
  for_each = var.parameters

  name  = "${local.prefix}/${each.key}"
  type  = "String"
  value = each.value
}
