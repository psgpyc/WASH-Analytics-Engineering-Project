output "bucket_name" {
  value       = aws_s3_bucket.this.bucket
  description = "S3 bucket name."
}

output "bucket_arn" {
  value       = aws_s3_bucket.this.arn
  description = "S3 bucket ARN."
}

output "bucket_id" {
  value       = aws_s3_bucket.this.id
  description = "S3 bucket ID (same as name for S3)."
}