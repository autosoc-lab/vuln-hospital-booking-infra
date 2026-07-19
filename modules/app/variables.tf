variable "project_name" {
  description = "리소스 네이밍에 사용할 프로젝트 이름"
  type        = string
}

variable "key_pair_name" {
  description = "EC2 SSH 키페어 이름"
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
