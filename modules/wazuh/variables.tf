variable "project_name" {
  description = "리소스 네이밍에 사용할 프로젝트 이름"
  type        = string
}

variable "common_tags" {
  description = "모든 리소스에 공통 적용할 태그"
  type        = map(string)
}

variable "account_id" {
  description = "현재 AWS 계정 ID"
  type        = string
}

variable "vpc_id" {
  description = "Wazuh 보안그룹을 배치할 VPC ID (networking 모듈에서 전달)"
  type        = string
}

variable "public_subnet_id" {
  description = "Wazuh EC2를 배치할 Public subnet ID (networking 모듈에서 전달)"
  type        = string
}

variable "key_pair_name" {
  description = "EC2 SSH 키페어 이름 (root 모듈에서 생성)"
  type        = string
}

variable "app_security_group_id" {
  description = "앱 EC2 보안그룹 ID — 여기서 오는 에이전트 트래픽만 허용 (networking 모듈에서 전달)"
  type        = string
}

variable "log_bucket_name" {
  description = "CloudTrail/VPC Flow Logs/GuardDuty가 쌓이는 S3 버킷명 (security_monitoring 모듈에서 전달)"
  type        = string
}

variable "log_bucket_arn" {
  description = "위 로그 버킷의 ARN"
  type        = string
}

variable "wazuh_version" {
  description = "설치할 Wazuh major.minor 버전 (app 모듈의 에이전트와 반드시 일치해야 함)"
  type        = string
}

variable "shuffle_private_ip" {
  description = "Shuffle SOAR EC2의 사설 IP. Wazuh integration이 웹훅을 VPC 내부로 보낼 대상 (shuffle SG가 외부 3001을 막으므로 사설IP로 전송)."
  type        = string
}

variable "shuffle_webhook_hook_id" {
  description = <<-EOT
    Shuffle "Wazuh Alert Router" 워크플로 웹훅 트리거의 id.
    bootstrap-import.sh가 이 id로 웹훅을 start하므로 재배포해도 URL이 고정된다
    (vuln-hospital-booking-soar/workflows/Wazuh Alert Router.json 의 WEBHOOK trigger id).
    워크플로의 웹훅 트리거를 새로 만들면 이 값을 그 id로 교체할 것.
  EOT
  type        = string
  default     = "8e84e673-e96b-4807-956d-92a05fb06ed3"
}

variable "shuffle_integration_level" {
  description = "이 레벨 이상의 Wazuh 알림만 Shuffle로 전달 (enable-shuffle-integration.sh 두 번째 인자)."
  type        = number
  default     = 6
}
