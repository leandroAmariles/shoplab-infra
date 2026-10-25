# Floci exige red e IAM aunque sea un emulador: VPC, subred y rol del plano de control.
resource "aws_vpc" "this" {
  cidr_block = "10.0.0.0/16"

  tags = {
    Name = var.cluster_name
  }
}

resource "aws_subnet" "this" {
  vpc_id     = aws_vpc.this.id
  cidr_block = "10.0.1.0/24"

  tags = {
    Name = var.cluster_name
  }
}

resource "aws_iam_role" "cluster" {
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
  name     = var.cluster_name
  version  = var.kubernetes_version
  role_arn = aws_iam_role.cluster.arn

  vpc_config {
    subnet_ids = [aws_subnet.this.id]
  }
}

# El token de aws_eks_cluster_auth sale con X-Amz-Expires=0 y k3s lo rechaza (research R4); se usa el certificado
# de cliente de k3s, que Floci deja en el contenedor floci-aws-eks-<cluster>.
data "external" "kubeconfig" {
  program = ["bash", "${path.module}/scripts/k3s-kubeconfig.sh"]

  query = {
    container = "floci-aws-eks-${aws_eks_cluster.this.name}"
    endpoint  = aws_eks_cluster.this.endpoint
  }
}
