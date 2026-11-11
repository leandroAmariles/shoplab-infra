mock_provider "aws" {}

variables {
  environment = "dev"
  secrets = {
    postgres-password = "valor-de-prueba-1"
    llm-api-key       = "valor-de-prueba-2"
    langfuse          = "{\"POSTGRES_PASSWORD\":\"valor-de-prueba-3\",\"CLICKHOUSE_PASSWORD\":\"valor-de-prueba-3\",\"REDIS_AUTH\":\"valor-de-prueba-3\",\"MINIO_ROOT_PASSWORD\":\"valor-de-prueba-3\",\"SALT\":\"valor-de-prueba-3\",\"ENCRYPTION_KEY\":\"valor-de-prueba-3\",\"NEXTAUTH_SECRET\":\"valor-de-prueba-3\",\"LANGFUSE_INIT_PROJECT_PUBLIC_KEY\":\"valor-de-prueba-3\",\"LANGFUSE_INIT_PROJECT_SECRET_KEY\":\"valor-de-prueba-3\",\"LANGFUSE_INIT_USER_PASSWORD\":\"valor-de-prueba-3\"}"
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
      langfuse          = "{\"POSTGRES_PASSWORD\":\"valor-de-prueba-3\",\"CLICKHOUSE_PASSWORD\":\"valor-de-prueba-3\",\"REDIS_AUTH\":\"valor-de-prueba-3\",\"MINIO_ROOT_PASSWORD\":\"valor-de-prueba-3\",\"SALT\":\"valor-de-prueba-3\",\"ENCRYPTION_KEY\":\"valor-de-prueba-3\",\"NEXTAUTH_SECRET\":\"valor-de-prueba-3\",\"LANGFUSE_INIT_PROJECT_PUBLIC_KEY\":\"valor-de-prueba-3\",\"LANGFUSE_INIT_PROJECT_SECRET_KEY\":\"valor-de-prueba-3\",\"LANGFUSE_INIT_USER_PASSWORD\":\"valor-de-prueba-3\"}"
    }
  }

  expect_failures = [var.secrets]
}
