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
  description = "GuardDuty Detector ID (enable_guardduty=false이면 null)"
  value       = try(aws_guardduty_detector.main[0].id, null)
}
