# El k3s de Floci no trae StorageClass: sin una por defecto, los PVC de Postgres y Ollama quedan en Pending y
# `shoplab-dev` no llega a Healthy. Chart local con local-path-provisioner (volúmenes hostPath en el nodo desechable).
resource "helm_release" "local_path_storage" {
  name             = "local-path-storage"
  namespace        = "local-path-storage"
  create_namespace = true
  chart            = "${path.module}/charts/local-path-storage"

  wait    = true
  timeout = 300
}
