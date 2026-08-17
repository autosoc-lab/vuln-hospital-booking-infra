variable "project_name" {
  description = "리소스 네이밍에 사용할 프로젝트 이름"
  type        = string
}

variable "common_tags" {
  description = "모든 리소스에 공통 적용할 태그"
  type        = map(string)
}

variable "vpc_id" {
  description = "Shuffle 보안그룹을 배치할 VPC ID (networking 모듈에서 전달)"
  type        = string
}

variable "public_subnet_id" {
  description = "Shuffle EC2를 배치할 Public subnet ID (networking 모듈에서 전달)"
  type        = string
}

variable "key_pair_name" {
  description = "EC2 SSH 키페어 이름 (root 모듈에서 생성)"
  type        = string
}

variable "soar_git_ref" {
  description = "EC2가 clone할 vuln-hospital-booking-soar 브랜치명"
  type        = string
  default     = "main"
}

variable "shuffle_admin_username" {
  description = "Shuffle 최초 관리자 계정명"
  type        = string
  default     = "admin"
}

variable "shuffle_admin_password" {
  description = "Shuffle 최초 관리자 비밀번호 (min length 8 권장)"
  type        = string
  sensitive   = true
}

variable "shuffle_encryption_modifier" {
  description = "Shuffle 앱 인증정보 암호화 시드 — 한 번 정하면 바꾸지 말 것 (openssl rand -hex 32)"
  type        = string
  sensitive   = true
}

variable "shuffle_opensearch_password" {
  description = "Shuffle 내장 OpenSearch 관리자 비밀번호 (대소문자/숫자/특수문자 포함 8자 이상)"
  type        = string
  sensitive   = true
}

variable "discord_webhook_url" {
  description = "Discord 웹훅 URL(시크릿). bootstrap-import.sh가 워크플로 import 시 Discord 노드 url에 주입. 비우면 주입 건너뜀."
  type        = string
  sensitive   = true
  default     = ""
}

variable "vpc_cidr" {
  description = "VPC CIDR. 3001/3443을 내부(Wazuh 웹훅)에서만 열기 위해 사용."
  type        = string
}

variable "admin_cidr" {
  description = "대시보드 접속 허용 관리자 IP CIDR. 빈 값이면 외부 접속 규칙을 추가하지 않음."
  type        = string
  default     = ""
}

variable "account_id" {
  description = "현재 AWS 계정 ID"
  type        = string
}

variable "app_security_group_id" {
  description = "정상 앱 EC2 보안그룹 ID"
  type        = string
}

variable "quarantine_security_group_id" {
  description = "침해 확증 시 앱 EC2에 적용할 격리 보안그룹 ID"
  type        = string
}
