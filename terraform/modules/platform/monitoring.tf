resource "helm_release" "kube_prometheus_stack" {
  name             = "kube-prometheus-stack"
  namespace        = "monitoring"
  create_namespace = true
  repository       = "https://prometheus-community.github.io/helm-charts"
  chart            = "kube-prometheus-stack"
  version          = var.chart_versions.kube_prometheus_stack

  # Pila base reducida para una máquina de desarrollo.
  values = [yamlencode({
    alertmanager = { enabled = false }
    # node-exporter necesita montajes del host que no existen en k3s dentro de Docker (CreateContainerError).
    nodeExporter = { enabled = false }
    "prometheus-node-exporter" = {
      enabled = false
    }
    prometheus = {
      prometheusSpec = {
        retention = "6h"
        resources = { requests = { cpu = "100m", memory = "400Mi" } }
      }
    }
    grafana = { resources = { requests = { cpu = "50m", memory = "128Mi" } } }
  })]

  wait    = true
  timeout = 900

  depends_on = [helm_release.external_secrets]
}
