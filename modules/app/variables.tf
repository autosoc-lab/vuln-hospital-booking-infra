variable "project_name" {
  description = "리소스 네이밍에 사용할 프로젝트 이름"
  type        = string
}

variable "key_pair_name" {
  description = "EC2 SSH 키페어 이름"
  type        = string
}

variable "app_git_ref" {
  description = "EC2 user_data가 clone할 vuln-hospital-booking 브랜치명"
  type        = string
}

variable "db_username" {
  description = "RDS PostgreSQL 마스터 사용자명"
  type        = string
}

variable "db_password" {
  description = "RDS PostgreSQL 마스터 비밀번호"
  type        = string
  sensitive   = true
}

variable "common_tags" {
  description = "모든 리소스에 공통 적용할 태그"
  type        = map(string)
}

variable "account_id" {
  description = "현재 AWS 계정 ID (S3 버킷명 등에 사용)"
  type        = string
}

variable "public_subnet_id" {
  description = "EC2를 배치할 Public subnet ID (networking 모듈에서 전달)"
  type        = string
}

variable "private_subnet_ids" {
  description = "RDS DB Subnet Group에 사용할 Private subnet ID 목록 (최소 2개 AZ, networking 모듈에서 전달)"
  type        = list(string)
}

variable "ec2_security_group_id" {
  description = "EC2에 적용할 보안그룹 ID (networking 모듈에서 전달)"
  type        = string
}

variable "rds_security_group_id" {
  description = "RDS에 적용할 보안그룹 ID (networking 모듈에서 전달)"
  type        = string
}

variable "wazuh_manager_private_ip" {
  description = "Wazuh 매니저 프라이빗 IP (wazuh 모듈에서 전달, agent 등록용)"
  type        = string
}
