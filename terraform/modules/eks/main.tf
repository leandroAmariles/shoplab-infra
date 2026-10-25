locals {
  floci = var.cluster_mode == "floci"
}

# Modo floci. Floci exige red e IAM aunque sea un emulador: VPC, subred y rol del plano de control.
resource "aws_vpc" "this" {
  count = local.floci ? 1 : 0

  cidr_block = "10.0.0.0/16"

  tags = {
    Name = var.cluster_name
  }
}

resource "aws_subnet" "this" {
  count = local.floci ? 1 : 0

  vpc_id     = aws_vpc.this[0].id
  cidr_block = "10.0.1.0/24"

  tags = {
    Name = var.cluster_name
  }
}

resource "aws_iam_role" "cluster" {
  count = local.floci ? 1 : 0

  name = "${var.cluster_name}-eks"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "eks.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_eks_cluster" "this" {
  count = local.floci ? 1 : 0

  name     = var.cluster_name
  version  = var.kubernetes_version
  role_arn = aws_iam_role.cluster[0].arn

  vpc_config {
    subnet_ids = [aws_subnet.this[0].id]
  }
}

# El token de aws_eks_cluster_auth sale con X-Amz-Expires=0 y k3s lo rechaza (research R4); se usa el certificado
# de cliente de k3s, que Floci deja en el contenedor floci-aws-eks-<cluster>.
data "external" "kubeconfig" {
  count = local.floci ? 1 : 0

  program = ["bash", "${path.module}/scripts/k3s-kubeconfig.sh"]

  query = {
    container = "floci-aws-eks-${aws_eks_cluster.this[0].name}"
    endpoint  = aws_eks_cluster.this[0].endpoint
  }
}

# Modo kind (respaldo si el EKS de Floci falla): expone el mismo contrato de salida.
resource "kind_cluster" "this" {
  count = local.floci ? 0 : 1

  name           = var.cluster_name
  node_image     = "kindest/node:v1.35.0"
  wait_for_ready = true
}

# Entornos aplicados antes de existir el modo kind: se conservan los recursos sin recrearlos.
moved {
  from = aws_vpc.this
  to   = aws_vpc.this[0]
}

moved {
  from = aws_subnet.this
  to   = aws_subnet.this[0]
}

moved {
  from = aws_iam_role.cluster
  to   = aws_iam_role.cluster[0]
}

moved {
  from = aws_eks_cluster.this
  to   = aws_eks_cluster.this[0]
}

moved {
  from = data.external.kubeconfig
  to   = data.external.kubeconfig[0]
}
