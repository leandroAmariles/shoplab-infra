resource "helm_release" "ingress_nginx" {
  name             = "ingress-nginx"
  namespace        = "ingress-nginx"
  create_namespace = true
  repository       = "https://kubernetes.github.io/ingress-nginx"
  chart            = "ingress-nginx"
  version          = var.chart_versions.ingress_nginx

  # NodePort: en kind un Service LoadBalancer nunca recibe IP externa y `wait` esperaría hasta el timeout.
  values = [yamlencode({
    controller = { service = { type = "NodePort" } }
  })]

  wait    = true
  timeout = 600
}
