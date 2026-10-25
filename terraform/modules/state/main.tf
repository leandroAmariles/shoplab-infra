# force_destroy: el bucket contiene el estado y el lock al destruir; solo existe en el emulador local.
resource "aws_s3_bucket" "state" {
  bucket        = var.bucket_name
  force_destroy = true

  tags = {
    Environment = var.environment
  }
}

resource "aws_s3_bucket_versioning" "state" {
  bucket = aws_s3_bucket.state.id

  versioning_configuration {
    status = "Enabled"
  }
}
