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

output "leaked_s3_key_access_key_id" {
  description = "SSE-C 실습용 '유출된' IAM 사용자 Access Key ID"
  value       = module.app.leaked_s3_key_access_key_id
}

output "leaked_s3_key_secret_access_key" {
  description = "SSE-C 실습용 '유출된' IAM 사용자 Secret Access Key"
  value       = module.app.leaked_s3_key_secret_access_key
  sensitive   = true
}

output "guardduty_detector_id" {
  description = "GuardDuty Detector ID"
  value       = module.security_monitoring.guardduty_detector_id
}

output "vpc_id" {
  description = "VPC ID"
  value       = module.networking.vpc_id
}

output "wazuh_dashboard_url" {
  description = "Wazuh 대시보드 URL (초기 로그인 정보는 SSH 접속 후 wazuh-install-files.tar 참고)"
  value       = "https://${module.wazuh.dashboard_public_ip}"
}
