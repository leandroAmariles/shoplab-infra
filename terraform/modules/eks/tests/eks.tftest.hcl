# Con mocks, apply no toca ningÃºn emulador: el data source external depende de un endpoint conocido solo al aplicar.
mock_provider "aws" {
  mock_resource "aws_iam_role" {
    defaults = {
      arn = "arn:aws:iam::000000000000:role/shoplab-dev-eks"
    }
  }

  mock_resource "aws_eks_cluster" {
    defaults = {
      endpoint = "https://localhost:6501"
    }
  }
}

mock_provider "kind" {
  mock_resource "kind_cluster" {
    defaults = {
      endpoint               = "https://127.0.0.1:6502"
      cluster_ca_certificate = "ca-pem"
      client_certificate     = "cert-pem"
      client_key             = "key-pem"
      kubeconfig             = "kind-kubeconfig"
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
  cluster_name = "shoplab-dev"
}

run "exposes_connection_contract" {
  command = apply

  assert {
    condition     = output.kubeconfig == "apiVersion: v1"
    error_message = "El mÃ³dulo eks debe exponer el output kubeconfig"
  }

  assert {
    condition     = output.cluster_ca_certificate == "Y2E="
    error_message = "El mÃ³dulo eks debe exponer cluster_ca_certificate"
  }

  assert {
    condition     = output.client_certificate == "Y2VydA==" && output.client_key == "a2V5"
    error_message = "El mÃ³dulo eks debe exponer client_certificate y client_key"
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

run "kind_mode_keeps_the_same_output_contract" {
  command = apply

  variables {
    cluster_mode = "kind"
  }

  assert {
    condition     = output.host == "https://127.0.0.1:6502"
    error_message = "En modo kind, host debe salir del clúster de kind"
  }

  assert {
    condition = (
      output.cluster_ca_certificate == base64encode("ca-pem") &&
      output.client_certificate == base64encode("cert-pem") &&
      output.client_key == base64encode("key-pem")
    )
    error_message = "En modo kind, las credenciales deben salir en base64 igual que en modo floci"
  }

  assert {
    condition     = output.kubeconfig == "kind-kubeconfig"
    error_message = "En modo kind, kubeconfig debe exponerse igual que en modo floci"
  }

  assert {
    condition     = length(aws_eks_cluster.this) == 0
    error_message = "En modo kind no se debe crear ningún clúster EKS emulado"
  }
}

run "floci_mode_does_not_create_a_kind_cluster" {
  command = apply

  assert {
    condition     = length(kind_cluster.this) == 0
    error_message = "En modo floci no se debe crear ningún clúster de kind"
  }
}
