output "ec2_public_ip" {
  description = "EC2 인스턴스 퍼블릭 IP (Elastic IP)"
  value       = module.app.ec2_public_ip
}

output "rds_endpoint" {
  description = "RDS PostgreSQL 엔드포인트"
  value       = module.app.rds_endpoint
}

output "log_bucket_name" {
  description = "CloudTrail/로그 저장 S3 버킷명"
  value       = module.security_monitoring.log_bucket_name
}

output "documents_bucket_name" {
  description = "환자 문서/생성 PDF 저장용 S3 버킷명"
  value       = module.app.documents_bucket_name
}

output "guardduty_detector_id" {
  description = "GuardDuty Detector ID"
  value       = module.security_monitoring.guardduty_detector_id
}

output "vpc_id" {
  description = "VPC ID"
  value       = module.networking.vpc_id
}
