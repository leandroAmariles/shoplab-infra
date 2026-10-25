# Con mocks, apply no toca ningún emulador: el data source external depende de un endpoint conocido solo al aplicar.
mock_provider "aws" {
  mock_resource "aws_iam_role" {
    defaults = {
      arn = "arn:aws:iam::000000000000:role/shoplab-local-eks"
    }
  }

  mock_resource "aws_eks_cluster" {
    defaults = {
      endpoint = "https://localhost:6501"
    }
  }
}

mock_provider "external" {
  mock_data "external" {
    defaults = {
      result = {
        kubeconfig             = "apiVersion: v1"
        cluster_ca_certificate = "Y2E="
        client_certificate     = "Y2VydA=="
        client_key             = "a2V5"
      }
    }
  }
}

variables {
  cluster_name = "shoplab-local"
}

run "exposes_connection_contract" {
  command = apply

  assert {
    condition     = output.kubeconfig == "apiVersion: v1"
    error_message = "El módulo eks debe exponer el output kubeconfig"
  }

  assert {
    condition     = output.cluster_ca_certificate == "Y2E="
    error_message = "El módulo eks debe exponer cluster_ca_certificate"
  }

  assert {
    condition     = output.client_certificate == "Y2VydA==" && output.client_key == "a2V5"
    error_message = "El módulo eks debe exponer client_certificate y client_key"
  }
}

run "defaults_to_floci_mode" {
  command = apply

  assert {
    condition     = var.cluster_mode == "floci"
    error_message = "El modo por defecto debe ser floci"
  }
}

run "rejects_unknown_cluster_mode" {
  command = plan

  variables {
    cluster_mode = "minikube"
  }

  expect_failures = [var.cluster_mode]
}
