output "log_bucket_name" {
  description = "CloudTrail/로그 저장 S3 버킷명"
  value       = aws_s3_bucket.logs.id
}

output "log_bucket_arn" {
  description = "로그 저장 S3 버킷 ARN"
  value       = aws_s3_bucket.logs.arn
}

output "cloudtrail_arn" {
  description = "CloudTrail ARN"
  value       = aws_cloudtrail.main.arn
}

output "guardduty_detector_id" {
  description = "GuardDuty Detector ID"
  value       = aws_guardduty_detector.main.id
}

output "vpc_flow_log_group_name" {
  description = "VPC Flow Logs CloudWatch Log Group 이름 (networking 모듈에서 참조)"
  value       = aws_cloudwatch_log_group.vpc_flow_logs.name
}

output "vpc_flow_log_group_arn" {
  description = "VPC Flow Logs CloudWatch Log Group ARN (networking 모듈에서 참조)"
  value       = aws_cloudwatch_log_group.vpc_flow_logs.arn
}

output "cloudtrail_log_group_name" {
  description = "CloudTrail CloudWatch Log Group 이름"
  value       = aws_cloudwatch_log_group.cloudtrail.name
}
