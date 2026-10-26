mock_provider "aws" {}

variables {
  bucket_name = "shoplab-tfstate-dev"
  environment = "dev"
}

run "creates_versioned_state_bucket" {
  command = plan

  assert {
    condition     = aws_s3_bucket.state.bucket == "shoplab-tfstate-dev"
    error_message = "El bucket de estado debe usar el nombre recibido"
  }

  assert {
    condition     = aws_s3_bucket_versioning.state.versioning_configuration[0].status == "Enabled"
    error_message = "El bucket de estado debe tener el versionado habilitado"
  }

  assert {
    condition     = aws_s3_bucket.state.tags["Environment"] == "dev"
    error_message = "El bucket debe etiquetarse con el ambiente"
  }
}

run "exposes_bucket_name_output" {
  command = plan

  assert {
    condition     = output.bucket_name == "shoplab-tfstate-dev"
    error_message = "El módulo debe exponer el output bucket_name"
  }
}
