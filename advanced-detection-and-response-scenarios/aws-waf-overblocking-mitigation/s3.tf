#--------------------------------------
# GuardDuty Findings 저장 S3 버킷 (Sumo Logic 연동)
#--------------------------------------
resource "aws_s3_bucket" "guardduty_events" {
  bucket        = "${var.name_s3_guardduty_events}-${random_id.suffix.hex}"
  force_destroy = true

  tags = {
    Name    = "${var.name_s3_guardduty_events}-${random_id.suffix.hex}"
    Purpose = "GuardDuty Findings Logs"
  }
}

resource "aws_s3_bucket_versioning" "guardduty_events" {
  bucket = aws_s3_bucket.guardduty_events.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "guardduty_events" {
  bucket = aws_s3_bucket.guardduty_events.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

#--------------------------------------
# 분석 로그/아카이브 S3 버킷
#--------------------------------------
resource "aws_s3_bucket" "logarchive" {
  bucket        = "${var.name_s3_logarchive}-${random_id.suffix.hex}"
  force_destroy = true

  tags = {
    Name    = "${var.name_s3_logarchive}-${random_id.suffix.hex}"
    Purpose = "Malware Forensic Log Archive"
  }
}

resource "aws_s3_bucket_versioning" "logarchive" {
  bucket = aws_s3_bucket.logarchive.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "logarchive" {
  bucket = aws_s3_bucket.logarchive.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

#--------------------------------------
# forensic-results 폴더(prefix) 생성 (S3는 폴더가 아닌 key prefix!)
#--------------------------------------
resource "aws_s3_object" "forensic_results_folder" {
  bucket  = aws_s3_bucket.logarchive.bucket
  key     = "forensic-results/"
  content = ""
}


/*
#--------------------------------------
# Sumo Logic 연동용 S3 버킷 정책 (Sumo Logic IAM 역할에만 접근 허용)
# (SUMO_ACCOUNT_ID 및 EXTERNAL_ID는 환경에 맞게 교체 필요)
#--------------------------------------
data "aws_caller_identity" "current" {}

resource "aws_s3_bucket_policy" "guardduty_events" {
  bucket = aws_s3_bucket.guardduty_events.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "SumoLogicS3ReadAccess"
        Effect    = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/${var.name_iam_sumologic_role}-${random_id.suffix.hex}"
        }
        Action = [
          "s3:GetObject",
          "s3:GetObjectVersion",
          "s3:ListBucket"
        ]
        Resource = [
          "${aws_s3_bucket.guardduty_events.arn}",
          "${aws_s3_bucket.guardduty_events.arn}/*"
        ]
      }
    ]
  })
}
*/
