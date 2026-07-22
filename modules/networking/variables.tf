variable "project_name" {
  description = "리소스 네이밍에 사용할 프로젝트 이름"
  type        = string
}

variable "common_tags" {
  description = "모든 리소스에 공통 적용할 태그"
  type        = map(string)
}

variable "flow_log_group_name" {
  description = "VPC Flow Logs를 전송할 CloudWatch Log Group 이름 (security_monitoring 모듈에서 생성)"
  type        = string
}

variable "flow_log_group_arn" {
  description = "VPC Flow Logs를 전송할 CloudWatch Log Group ARN (security_monitoring 모듈에서 생성)"
  type        = string
}

variable "log_bucket_arn" {
  description = "VPC Flow Logs를 추가로 전송할 S3 로그 버킷 ARN (security_monitoring 모듈에서 생성, Wazuh가 읽어감)"
  type        = string
}
