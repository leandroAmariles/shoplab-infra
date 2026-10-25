mock_provider "helm" {}
mock_provider "kubernetes" {}

variables {
  chart_versions = {
    ingress_nginx         = "4.15.1"
    external_secrets      = "2.14.0"
    kube_prometheus_stack = "92.13.1"
    argo_cd               = "10.11.1"
  }
}

run "installs_four_platform_components_with_pinned_versions" {
  command = plan

  assert {
    condition     = helm_release.ingress_nginx.version == "4.15.1"
    error_message = "ingress-nginx debe usar la versión exacta recibida"
  }

  assert {
    condition     = helm_release.external_secrets.version == "2.14.0"
    error_message = "external-secrets debe usar la versión exacta recibida"
  }

  assert {
    condition     = helm_release.kube_prometheus_stack.version == "92.13.1"
    error_message = "kube-prometheus-stack debe usar la versión exacta recibida"
  }

  assert {
    condition     = helm_release.argo_cd.version == "10.11.1"
    error_message = "argo-cd debe usar la versión exacta recibida"
  }
}

run "uses_the_given_redis_image_repository_for_argocd" {
  command = plan

  variables {
    argocd_redis_image_repository = "mirror.gcr.io/library/redis"
  }

  assert {
    condition     = one([for s in helm_release.argo_cd.set : s.value if s.name == "redis.image.repository"]) == "mirror.gcr.io/library/redis"
    error_message = "Argo CD debe usar el repositorio de Redis recibido"
  }
}

run "rejects_a_redis_image_repository_with_a_tag" {
  command = plan

  variables {
    argocd_redis_image_repository = "mirror.gcr.io/library/redis:latest"
  }

  expect_failures = [var.argocd_redis_image_repository]
}

run "exposes_installed_components_and_argocd_url" {
  command = plan

  assert {
    condition     = length(output.installed_components) == 4
    error_message = "installed_components debe listar los cuatro componentes"
  }

  assert {
    condition     = output.argocd_url != ""
    error_message = "El módulo debe exponer argocd_url"
  }
}

run "rejects_latest_chart_version" {
  command = plan

  variables {
    chart_versions = {
      ingress_nginx         = "latest"
      external_secrets      = "2.14.0"
      kube_prometheus_stack = "92.13.1"
      argo_cd               = "10.11.1"
    }
  }

  expect_failures = [var.chart_versions]
}

run "rejects_open_range_chart_version" {
  command = plan

  variables {
    chart_versions = {
      ingress_nginx         = "4.15.1"
      external_secrets      = ">= 2.0.0"
      kube_prometheus_stack = "92.13.1"
      argo_cd               = "10.11.1"
    }
  }

  expect_failures = [var.chart_versions]
}
