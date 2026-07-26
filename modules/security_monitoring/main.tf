# --- S3 버킷 (로그 저장소) ---
# force_destroy = true — 실습 종료 후 terraform destroy 시 버전 포함 객체가 남아있어도
# 자동으로 비우고 삭제 (버저닝 켜져 있어 수동 정리가 번거로움)
resource "aws_s3_bucket" "logs" {
  bucket        = "${var.project_name}-logs-${var.account_id}"
  force_destroy = true

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

# CloudTrail/VPC Flow Logs/GuardDuty가 로그를 쓸 수 있도록 허용하는 버킷 정책
# (Wazuh 매니저의 wodle aws-s3 모듈이 이 버킷을 읽어감)
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

  statement {
    sid    = "AWSLogDeliveryAclCheck"
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["delivery.logs.amazonaws.com"]
    }

    actions   = ["s3:GetBucketAcl"]
    resources = [aws_s3_bucket.logs.arn]
  }

  statement {
    sid    = "AWSLogDeliveryWrite"
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["delivery.logs.amazonaws.com"]
    }

    actions   = ["s3:PutObject"]
    resources = ["${aws_s3_bucket.logs.arn}/AWSLogs/${var.account_id}/vpcflowlogs/*"]

    condition {
      test     = "StringEquals"
      variable = "s3:x-amz-acl"
      values   = ["bucket-owner-full-control"]
    }
  }

  statement {
    sid    = "AWSGuardDutyGetBucketLocation"
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["guardduty.amazonaws.com"]
    }

    actions   = ["s3:GetBucketLocation"]
    resources = [aws_s3_bucket.logs.arn]

    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [var.account_id]
    }
  }

  statement {
    sid    = "AWSGuardDutyPutObject"
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["guardduty.amazonaws.com"]
    }

    actions   = ["s3:PutObject"]
    resources = ["${aws_s3_bucket.logs.arn}/guardduty/*"]

    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [var.account_id]
    }
  }
}

resource "aws_s3_bucket_policy" "logs" {
  bucket = aws_s3_bucket.logs.id
  policy = data.aws_iam_policy_document.logs_bucket_policy.json
}

# --- CloudTrail ---
resource "aws_cloudtrail" "main" {
  name                       = "${var.project_name}-trail"
  s3_bucket_name             = aws_s3_bucket.logs.id
  is_multi_region_trail      = false
  enable_log_file_validation = true

  # advanced_event_selector를 하나라도 쓰면 기본 관리 이벤트 로깅이 대체되므로
  # 관리 이벤트용 셀렉터를 명시적으로 유지한다.
  advanced_event_selector {
    name = "Management events"

    field_selector {
      field  = "eventCategory"
      equals = ["Management"]
    }
  }

  # documents 버킷의 객체 단위 이벤트(GetObject/PutObject)를 데이터 이벤트로 수집.
  # 기본값은 비활성이라 SSRF→S3 sync(exfil)/SSE-C 재암호화 탐지 룰이 CloudTrail을
  # 통해 아무것도 볼 수 없었음 (SSE-C.md 3.4 "탐지 강화" 권고 반영).
  advanced_event_selector {
    name = "Documents bucket S3 object-level events"

    field_selector {
      field  = "eventCategory"
      equals = ["Data"]
    }

    field_selector {
      field  = "resources.type"
      equals = ["AWS::S3::Object"]
    }

    field_selector {
      field       = "resources.ARN"
      starts_with = ["arn:aws:s3:::${var.project_name}-documents-${var.account_id}/"]
    }
  }

  depends_on = [aws_s3_bucket_policy.logs]

  tags = var.common_tags
}

# --- GuardDuty ---
# free tier/신규 계정은 GuardDuty 구독이 안 되어 있을 수 있음 (SubscriptionRequiredException) —
# var.enable_guardduty로 껐다 켤 수 있게 분리. 계정 인증이 끝나면 true로 바꿔서 재적용.
# 기본 탐지기 — CloudTrail 이벤트, VPC Flow Logs, DNS 로그를 분석하여
# 정찰(recon), 자격증명 침해(credential compromise), C2 통신, 크립토재킹 등을 탐지
resource "aws_guardduty_detector" "main" {
  count = var.enable_guardduty ? 1 : 0

  enable                       = true
  finding_publishing_frequency = "FIFTEEN_MINUTES"

  tags = var.common_tags
}

# S3 Protection — S3 데이터 이벤트(GetObject/PutObject 등)를 분석하여
# 비정상적인 대량 다운로드, 알려진 악성 IP/Tor 노드에서의 접근, 자격증명 오남용을 탐지
resource "aws_guardduty_detector_feature" "s3_protection" {
  count = var.enable_guardduty ? 1 : 0

  detector_id = aws_guardduty_detector.main[0].id
  name        = "S3_DATA_EVENTS"
  status      = "ENABLED"
}

# --- GuardDuty Findings를 S3로 내보내기 (Wazuh wodle aws-s3가 읽어갈 대상) ---
# GuardDuty의 S3 export 기능은 SSE-KMS 암호화를 요구하므로 전용 KMS 키를 생성한다.
resource "aws_kms_key" "guardduty" {
  count = var.enable_guardduty ? 1 : 0

  description             = "${var.project_name} GuardDuty findings export용 KMS 키"
  deletion_window_in_days = 7

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "EnableRootAccountAccess"
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${var.account_id}:root"
        }
        Action   = "kms:*"
        Resource = "*"
      },
      {
        Sid    = "AllowGuardDutyEncrypt"
        Effect = "Allow"
        Principal = {
          Service = "guardduty.amazonaws.com"
        }
        Action   = "kms:GenerateDataKey"
        Resource = "*"
        Condition = {
          StringEquals = {
            "aws:SourceAccount" = var.account_id
          }
          ArnLike = {
            "aws:SourceArn" = aws_guardduty_detector.main[0].arn
          }
        }
      }
    ]
  })

  tags = merge(var.common_tags, {
    Name = "${var.project_name}-guardduty-kms"
  })
}

resource "aws_guardduty_publishing_destination" "s3" {
  count = var.enable_guardduty ? 1 : 0

  detector_id     = aws_guardduty_detector.main[0].id
  destination_arn = "${aws_s3_bucket.logs.arn}/guardduty"
  kms_key_arn     = aws_kms_key.guardduty[0].arn

  depends_on = [aws_s3_bucket_policy.logs]
}
