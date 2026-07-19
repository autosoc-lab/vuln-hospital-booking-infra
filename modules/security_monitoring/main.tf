# --- CloudWatch Log Groups ---
# VPC Flow Logs 수신 — networking 모듈의 aws_flow_log가 이 로그 그룹을 참조한다
resource "aws_cloudwatch_log_group" "vpc_flow_logs" {
  name              = "/aws/vpc/flowlogs"
  retention_in_days = 30

  tags = var.common_tags
}

# CloudTrail 로그 수신
resource "aws_cloudwatch_log_group" "cloudtrail" {
  name              = "/aws/cloudtrail/${var.project_name}"
  retention_in_days = 30

  tags = var.common_tags
}

# --- S3 버킷 (로그 저장소) ---
resource "aws_s3_bucket" "logs" {
  bucket = "${var.project_name}-logs-${var.account_id}"

  tags = merge(var.common_tags, {
    Name = "${var.project_name}-logs"
  })
}

resource "aws_s3_bucket_public_access_block" "logs" {
  bucket = aws_s3_bucket.logs.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_versioning" "logs" {
  bucket = aws_s3_bucket.logs.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "logs" {
  bucket = aws_s3_bucket.logs.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "logs" {
  bucket = aws_s3_bucket.logs.id

  rule {
    id     = "log-retention"
    status = "Enabled"

    filter {}

    transition {
      days          = 90
      storage_class = "GLACIER"
    }

    expiration {
      days = 365
    }
  }
}

# CloudTrail이 로그를 쓸 수 있도록 허용하는 버킷 정책
data "aws_iam_policy_document" "logs_bucket_policy" {
  statement {
    sid    = "AWSCloudTrailAclCheck"
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["cloudtrail.amazonaws.com"]
    }

    actions   = ["s3:GetBucketAcl"]
    resources = [aws_s3_bucket.logs.arn]
  }

  statement {
    sid    = "AWSCloudTrailWrite"
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["cloudtrail.amazonaws.com"]
    }

    actions   = ["s3:PutObject"]
    resources = ["${aws_s3_bucket.logs.arn}/AWSLogs/${var.account_id}/*"]

    condition {
      test     = "StringEquals"
      variable = "s3:x-amz-acl"
      values   = ["bucket-owner-full-control"]
    }
  }
}

resource "aws_s3_bucket_policy" "logs" {
  bucket = aws_s3_bucket.logs.id
  policy = data.aws_iam_policy_document.logs_bucket_policy.json
}

# --- CloudTrail ---
# CloudTrail → CloudWatch Logs 전송용 IAM Role
resource "aws_iam_role" "cloudtrail_to_cloudwatch" {
  name = "${var.project_name}-cloudtrail-cwl-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "cloudtrail.amazonaws.com"
      }
      Action = "sts:AssumeRole"
    }]
  })

  tags = var.common_tags
}

resource "aws_iam_role_policy" "cloudtrail_to_cloudwatch" {
  name = "${var.project_name}-cloudtrail-cwl-policy"
  role = aws_iam_role.cloudtrail_to_cloudwatch.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "logs:CreateLogStream",
        "logs:PutLogEvents"
      ]
      Resource = "${aws_cloudwatch_log_group.cloudtrail.arn}:*"
    }]
  })
}

resource "aws_cloudtrail" "main" {
  name                          = "${var.project_name}-trail"
  s3_bucket_name                = aws_s3_bucket.logs.id
  is_multi_region_trail         = false
  enable_log_file_validation    = true
  cloud_watch_logs_group_arn    = "${aws_cloudwatch_log_group.cloudtrail.arn}:*"
  cloud_watch_logs_role_arn     = aws_iam_role.cloudtrail_to_cloudwatch.arn

  depends_on = [aws_s3_bucket_policy.logs]

  tags = var.common_tags
}

# --- GuardDuty ---
# 기본 탐지기 — CloudTrail 이벤트, VPC Flow Logs, DNS 로그를 분석하여
# 정찰(recon), 자격증명 침해(credential compromise), C2 통신, 크립토재킹 등을 탐지
resource "aws_guardduty_detector" "main" {
  enable                       = true
  finding_publishing_frequency = "FIFTEEN_MINUTES"

  tags = var.common_tags
}

# S3 Protection — S3 데이터 이벤트(GetObject/PutObject 등)를 분석하여
# 비정상적인 대량 다운로드, 알려진 악성 IP/Tor 노드에서의 접근, 자격증명 오남용을 탐지
resource "aws_guardduty_detector_feature" "s3_protection" {
  detector_id = aws_guardduty_detector.main.id
  name        = "S3_DATA_EVENTS"
  status      = "ENABLED"
}
