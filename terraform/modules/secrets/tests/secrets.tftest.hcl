mock_provider "aws" {}

variables {
  environment = "dev"
  secrets = {
    postgres-password = "valor-de-prueba-1"
    llm-api-key       = "valor-de-prueba-2"
  }
  parameters = {
    llm-model = "llama3"
  }
}

run "creates_secrets_and_parameters_under_environment_prefix" {
  command = plan

  assert {
    condition     = contains(output.secret_names, "/shoplab/dev/postgres-password")
    error_message = "Los secretos deben crearse bajo /shoplab/<ambiente>/"
  }

  assert {
    condition     = contains(output.parameter_names, "/shoplab/dev/llm-model")
    error_message = "Los parámetros deben crearse bajo /shoplab/<ambiente>/"
  }
}

run "does_not_expose_secret_values_in_outputs" {
  command = plan

  assert {
    condition     = !contains(output.secret_names, "valor-de-prueba-1")
    error_message = "Los outputs solo pueden contener nombres, nunca valores"
  }
}

run "fails_clearly_when_a_required_secret_is_missing" {
  command = plan

  variables {
    secrets = {
      postgres-password = "valor-de-prueba-1"
    }
  }

  expect_failures = [var.secrets]
}

run "fails_when_a_required_secret_is_empty" {
  command = plan

  variables {
    secrets = {
      postgres-password = ""
      llm-api-key       = "valor-de-prueba-2"
    }
  }

  expect_failures = [var.secrets]
}
