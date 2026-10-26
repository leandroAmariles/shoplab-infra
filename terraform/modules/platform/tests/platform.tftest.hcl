mock_provider "helm" {}
mock_provider "kubernetes" {}

variables {
  argocd_initial_app = {
    apiVersion = "argoproj.io/v1alpha1"
    kind       = "Application"
    metadata = {
      name       = "shoplab-root"
      namespace  = "argocd"
      finalizers = ["resources-finalizer.argocd.argoproj.io"]
    }
    spec = {
      project = "default"
      source = {
        repoURL        = "https://github.com/leandroAmariles/shoplab-infra"
        targetRevision = "main"
        path           = "k8s/argocd"
      }
      destination = {
        server    = "https://kubernetes.default.svc"
        namespace = "argocd"
      }
      syncPolicy = {
        automated = { prune = true, selfHeal = true }
      }
    }
  }

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

run "creates_the_root_application_from_the_given_manifest" {
  command = plan

  assert {
    condition     = yamldecode(helm_release.argocd_initial_app.values[0]).application.metadata.name == "shoplab-root"
    error_message = "La Application inicial debe ser la raíz recibida"
  }

  assert {
    condition     = yamldecode(helm_release.argocd_initial_app.values[0]).application.spec.source.path == "k8s/argocd"
    error_message = "La raíz debe sincronizar k8s/argocd"
  }

  assert {
    condition = (
      yamldecode(helm_release.argocd_initial_app.values[0]).application.spec.syncPolicy.automated.prune &&
      yamldecode(helm_release.argocd_initial_app.values[0]).application.spec.syncPolicy.automated.selfHeal
    )
    error_message = "La raíz debe sincronizar con prune y selfHeal"
  }

  assert {
    condition     = contains(yamldecode(helm_release.argocd_initial_app.values[0]).application.metadata.finalizers, "resources-finalizer.argocd.argoproj.io")
    error_message = "La raíz debe llevar el finalizer de Argo CD"
  }
}

run "rejects_a_template_repo_url_in_the_initial_app" {
  command = plan

  variables {
    argocd_initial_app = {
      kind = "Application"
      spec = { source = { repoURL = "https://github.com/CAMBIA-ESTE-OWNER/shoplab-infra", targetRevision = "main" } }
    }
  }

  expect_failures = [var.argocd_initial_app]
}

run "rejects_an_initial_app_that_does_not_follow_main" {
  command = plan

  variables {
    argocd_initial_app = {
      kind = "Application"
      spec = { source = { repoURL = "https://github.com/leandroAmariles/shoplab-infra", targetRevision = "HEAD" } }
    }
  }

  expect_failures = [var.argocd_initial_app]
}

run "rejects_an_initial_app_that_is_not_an_application" {
  command = plan

  variables {
    argocd_initial_app = {
      kind = "Deployment"
      spec = { source = { repoURL = "https://github.com/leandroAmariles/shoplab-infra", targetRevision = "main" } }
    }
  }

  expect_failures = [var.argocd_initial_app]
}

run "exposes_argocd_through_the_local_ingress" {
  command = plan

  assert {
    condition     = yamldecode(helm_release.argo_cd.values[0]).server.ingress.enabled == true
    error_message = "Argo CD debe publicarse con un ingress"
  }

  assert {
    condition     = yamldecode(helm_release.argo_cd.values[0]).server.ingress.ingressClassName == "nginx"
    error_message = "El ingress de Argo CD debe usar la clase nginx"
  }

  assert {
    condition     = yamldecode(helm_release.argo_cd.values[0]).server.ingress.hostname == "argocd.localtest.me"
    error_message = "El ingress de Argo CD debe usar el host por defecto argocd.localtest.me"
  }

  assert {
    condition     = yamldecode(helm_release.argo_cd.values[0]).configs.params["server.insecure"] == true
    error_message = "Argo CD debe servir HTTP detrás del ingress (server.insecure)"
  }

  assert {
    condition     = output.argocd_url == "http://argocd.localtest.me:8080"
    error_message = "argocd_url debe apuntar al host del ingress"
  }
}

run "uses_the_given_argocd_host" {
  command = plan

  variables {
    argocd_host = "gitops.localtest.me"
  }

  assert {
    condition     = yamldecode(helm_release.argo_cd.values[0]).server.ingress.hostname == "gitops.localtest.me"
    error_message = "El ingress debe usar el host recibido"
  }
}

run "rejects_an_argocd_host_outside_localtest_me" {
  command = plan

  variables {
    argocd_host = "argocd.example.com"
  }

  expect_failures = [var.argocd_host]
}

run "enables_alertmanager_with_minimal_resources" {
  command = plan

  assert {
    condition     = yamldecode(helm_release.kube_prometheus_stack.values[0]).alertmanager.enabled == true
    error_message = "Alertmanager debe estar activo: la alerta BackendDown (LAB-102) llega a él"
  }

  assert {
    condition = (
      yamldecode(helm_release.kube_prometheus_stack.values[0]).alertmanager.alertmanagerSpec.resources.requests.cpu == "10m" &&
      yamldecode(helm_release.kube_prometheus_stack.values[0]).alertmanager.alertmanagerSpec.resources.requests.memory == "32Mi"
    )
    error_message = "Alertmanager debe pedir solo 10m de CPU y 32Mi de memoria (el k3s local tiene ~2 CPU)"
  }

  assert {
    condition     = !can(yamldecode(helm_release.kube_prometheus_stack.values[0]).alertmanager.alertmanagerSpec.storage)
    error_message = "Alertmanager no debe pedir almacenamiento: el k3s de Floci no trae StorageClass"
  }
}

run "selects_every_service_monitor_and_rule" {
  command = plan

  assert {
    condition     = yamldecode(helm_release.kube_prometheus_stack.values[0]).prometheus.prometheusSpec.serviceMonitorSelectorNilUsesHelmValues == false
    error_message = "Prometheus debe seleccionar todos los ServiceMonitor, no solo los del release de Helm"
  }

  assert {
    condition     = yamldecode(helm_release.kube_prometheus_stack.values[0]).prometheus.prometheusSpec.ruleSelectorNilUsesHelmValues == false
    error_message = "Prometheus debe seleccionar todas las PrometheusRule, no solo las del release de Helm"
  }
}
