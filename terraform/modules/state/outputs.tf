output "bucket_name" {
  description = "Bucket de estado creado (para backend.tf)"
  value       = aws_s3_bucket.state.bucket
}
