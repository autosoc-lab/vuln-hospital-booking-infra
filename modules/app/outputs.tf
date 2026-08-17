output "ec2_public_ip" {
  description = "EC2 인스턴스 퍼블릭 IP (Elastic IP)"
  value       = aws_eip.app.public_ip
}

output "ec2_instance_id" {
  description = "앱 EC2 인스턴스 ID"
  value       = aws_instance.app.id
}

output "ec2_instance_arn" {
  description = "앱 EC2 인스턴스 ARN"
  value       = aws_instance.app.arn
}

output "ec2_role_name" {
  description = "앱 EC2 IAM role 이름"
  value       = aws_iam_role.ec2_ssm.name
}

output "ec2_role_arn" {
  description = "앱 EC2 IAM role ARN"
  value       = aws_iam_role.ec2_ssm.arn
}

output "rds_endpoint" {
  description = "RDS PostgreSQL 엔드포인트"
  value       = aws_db_instance.postgres.endpoint
}

output "documents_bucket_name" {
  description = "문서 저장용 S3 버킷명"
  value       = aws_s3_bucket.documents.bucket
}

output "documents_bucket_arn" {
  description = "문서 저장용 S3 버킷 ARN"
  value       = aws_s3_bucket.documents.arn
}

output "leaked_s3_key_user_name" {
  description = "SSE-C 실습용 유출 IAM 사용자 이름"
  value       = aws_iam_user.leaked_s3_key.name
}

output "leaked_s3_key_user_arn" {
  description = "SSE-C 실습용 유출 IAM 사용자 ARN"
  value       = aws_iam_user.leaked_s3_key.arn
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
