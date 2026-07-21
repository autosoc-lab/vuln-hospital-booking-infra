# 대상 리전
variable "aws_region" {
  description = "리소스를 배포할 AWS 리전"
  type        = string
  default     = "ap-northeast-2"
}

# 프로젝트 식별자 — 모든 리소스명/태그에 사용
variable "project_name" {
  description = "프로젝트 이름 (리소스 네이밍 및 태깅에 사용)"
  type        = string
  default     = "vuln-hospital"
}

# EC2 SSH 접속용 키페어 — 사전에 AWS 콘솔/CLI로 생성 필요
variable "key_pair_name" {
  description = "EC2 인스턴스에 연결할 SSH 키페어 이름"
  type        = string
}

# EC2가 clone할 앱 저장소의 브랜치 — SQLi 실습 코드가 병합된 브랜치
variable "app_git_ref" {
  description = "EC2 user_data가 clone할 vuln-hospital-booking 브랜치명"
  type        = string
  default     = "lab/sqli-ec2-rds"
}

# RDS PostgreSQL 관리자 계정
variable "db_username" {
  description = "RDS PostgreSQL 마스터 사용자명"
  type        = string
  default     = "hospital"
}

variable "db_password" {
  description = "RDS PostgreSQL 마스터 비밀번호"
  type        = string
  sensitive   = true
}

# 현재 호출자의 AWS 계정 ID — S3 버킷명 등에 사용
data "aws_caller_identity" "current" {}

locals {
  account_id = data.aws_caller_identity.current.account_id

  common_tags = {
    Project     = var.project_name
    Environment = "lab"
    Purpose     = "siem-soar-practice"
    ManagedBy   = "terraform"
  }
}
