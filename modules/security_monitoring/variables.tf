variable "project_name" {
  description = "리소스 네이밍에 사용할 프로젝트 이름"
  type        = string
}

variable "account_id" {
  description = "S3 버킷명 등에 사용할 AWS 계정 ID"
  type        = string
}

variable "common_tags" {
  description = "모든 리소스에 공통 적용할 태그"
  type        = map(string)
}
