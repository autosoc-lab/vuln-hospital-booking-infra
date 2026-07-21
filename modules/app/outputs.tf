output "ec2_public_ip" {
  description = "EC2 인스턴스 퍼블릭 IP (Elastic IP)"
  value       = aws_eip.app.public_ip
}

output "rds_endpoint" {
  description = "RDS PostgreSQL 엔드포인트"
  value       = aws_db_instance.postgres.endpoint
}

output "documents_bucket_name" {
  description = "문서 저장용 S3 버킷명"
  value       = aws_s3_bucket.documents.bucket
}

output "leaked_s3_key_access_key_id" {
  description = "SSE-C 실습용 '유출된' IAM 사용자 Access Key ID"
  value       = aws_iam_access_key.leaked_s3_key.id
}

output "leaked_s3_key_secret_access_key" {
  description = "SSE-C 실습용 '유출된' IAM 사용자 Secret Access Key"
  value       = aws_iam_access_key.leaked_s3_key.secret
  sensitive   = true
}
