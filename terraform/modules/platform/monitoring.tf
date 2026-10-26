resource "helm_release" "kube_prometheus_stack" {
  name             = "kube-prometheus-stack"
  namespace        = "monitoring"
  create_namespace = true
  repository       = "https://prometheus-community.github.io/helm-charts"
  chart            = "kube-prometheus-stack"
  version          = var.chart_versions.kube_prometheus_stack

  # Pila base reducida para una máquina de desarrollo.
  values = [yamlencode({
    # Alertmanager recibe la alerta BackendDown (LAB-102). Sin almacenamiento: el k3s de Floci no trae StorageClass, así
    # que un PVC dejaría el pod en Pending; las alertas silenciadas se pierden al reiniciar, aceptable en el laboratorio.
    alertmanager = {
      enabled = true
      alertmanagerSpec = {
        resources = { requests = { cpu = "10m", memory = "32Mi" } }
      }
    }
    # node-exporter necesita montajes del host que no existen en k3s dentro de Docker (CreateContainerError).
    nodeExporter = { enabled = false }
    "prometheus-node-exporter" = {
      enabled = false
    }
    prometheus = {
      prometheusSpec = {
        retention = "6h"
        # Con los valores por defecto del chart, Prometheus solo selecciona ServiceMonitor y PrometheusRule con la
        # etiqueta release: kube-prometheus-stack y descarta el resto en silencio. Se abre a todos para no acoplar los
        # manifiestos de k8s/ al nombre del release de Helm.
        serviceMonitorSelectorNilUsesHelmValues = false
        ruleSelectorNilUsesHelmValues           = false
        resources                               = { requests = { cpu = "100m", memory = "400Mi" } }
      }
    }
    grafana = { resources = { requests = { cpu = "50m", memory = "128Mi" } } }
  })]

  wait    = true
  timeout = 900

  depends_on = [helm_release.external_secrets]
}
