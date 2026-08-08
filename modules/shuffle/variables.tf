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
