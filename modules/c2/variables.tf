variable "project_name" {
  description = "리소스 네이밍에 사용할 프로젝트 이름"
  type        = string
}

variable "common_tags" {
  description = "모든 리소스에 공통 적용할 태그"
  type        = map(string)
}

variable "public_subnet_id" {
  description = "C2 수집 서버 EC2를 배치할 Public subnet ID (networking 모듈에서 전달)"
  type        = string
}

variable "key_pair_name" {
  description = "EC2 SSH 키페어 이름 (root 모듈에서 생성, app/wazuh와 공유)"
  type        = string
}

variable "c2_git_ref" {
  description = "vuln-hospital-booking-c2 레포에서 clone할 브랜치명"
  type        = string
  default     = "main"
}

variable "c2_lab_token" {
  description = "수집 서버 /upload 엔드포인트 인증 토큰 (X-Lab-Token 헤더)"
  type        = string
  sensitive   = true
}
