# TFLint de shoplab-infra (LAB-99). La versión del plugin debe coincidir con TFLINT_AWS_RULESET_VERSION de versions.env.
plugin "terraform" {
  enabled = true
  preset  = "recommended"
}

plugin "aws" {
  enabled = true
  version = "0.50.0"
  source  = "github.com/terraform-linters/tflint-ruleset-aws"
}
