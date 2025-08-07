data "aws_caller_identity" "current" {}

provider "aws" {
  region = "ap-northeast-2"
}

# ✅ S3 버킷 (CloudTrail 로그 저장용)
resource "aws_s3_bucket" "cloudtrail_logs" {
  bucket        = var.s3_bucket_name
  force_destroy = true
}

resource "aws_s3_bucket_versioning" "cloudtrail_logs_versioning" {
  bucket = aws_s3_bucket.cloudtrail_logs.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "cloudtrail_logs_sse" {
  bucket = aws_s3_bucket.cloudtrail_logs.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_policy" "cloudtrail_logs_policy" {
  bucket = aws_s3_bucket.cloudtrail_logs.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "AWSCloudTrailAclCheck"
        Effect    = "Allow"
        Principal = { Service = "cloudtrail.amazonaws.com" }
        Action    = "s3:GetBucketAcl"
        Resource  = "arn:aws:s3:::${aws_s3_bucket.cloudtrail_logs.id}"
      },
      {
        Sid       = "AWSCloudTrailWrite"
        Effect    = "Allow"
        Principal = { Service = "cloudtrail.amazonaws.com" }
        Action    = "s3:PutObject"
        Resource  = "arn:aws:s3:::${aws_s3_bucket.cloudtrail_logs.id}/AWSLogs/${data.aws_caller_identity.current.account_id}/*"
        Condition = {
          StringEquals = {
            "s3:x-amz-acl" = "bucket-owner-full-control"
          }
        }
      }
    ]
  })
}

resource "aws_s3_bucket_ownership_controls" "cloudtrail_logs_ownership" {
  bucket = aws_s3_bucket.cloudtrail_logs.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_public_access_block" "cloudtrail_logs_block" {
  bucket                  = aws_s3_bucket.cloudtrail_logs.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# ✅ CloudTrail
resource "aws_cloudtrail" "audit" {
  name                          = var.cloudtrail_name
  s3_bucket_name                = aws_s3_bucket.cloudtrail_logs.id
  enable_log_file_validation    = true
  is_multi_region_trail         = true
  include_global_service_events = true

  event_selector {
    read_write_type           = "All"
    include_management_events = true
  }

  depends_on = [aws_s3_bucket_policy.cloudtrail_logs_policy]
}

# ✅ Glue IAM Role
resource "aws_iam_role" "glue" {
  name               = var.glue_role_name
  assume_role_policy = data.aws_iam_policy_document.glue_assume_role_policy.json
}

# Glue 서비스 AssumeRole 정책
data "aws_iam_policy_document" "glue_assume_role_policy" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["glue.amazonaws.com"]
    }
  }
}

# Glue 서비스 기본 역할 정책 Attach
resource "aws_iam_role_policy_attachment" "glue_attach" {
  role       = aws_iam_role.glue.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSGlueServiceRole"
}

# Glue 서비스 역할에 S3 접근 정책 추가 (403 오류 방지)
resource "aws_iam_policy" "glue_s3_access" {
  name        = "GlueS3AccessPolicy"
  description = "Allow Glue Crawler to access CloudTrail S3 bucket"
  policy      = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:ListBucket",
          "s3:GetObject"
        ]
        Resource = [
          "arn:aws:s3:::${aws_s3_bucket.cloudtrail_logs.id}",
          "arn:aws:s3:::${aws_s3_bucket.cloudtrail_logs.id}/*"
        ]
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "glue_s3_access_attach" {
  role       = aws_iam_role.glue.name
  policy_arn = aws_iam_policy.glue_s3_access.arn
}

# ✅ Athena Database
resource "aws_glue_catalog_database" "athena_db" {
  name = var.athena_db
}

# ✅ Athena Table
resource "aws_glue_catalog_table" "cloudtrail_table" {
  name          = var.athena_table
  database_name = aws_glue_catalog_database.athena_db.name
  table_type    = "EXTERNAL_TABLE"

  parameters = {
    "classification"  = "json"
    "compressionType"  = "none"
    "typeOfData"       = "file"
  }

  storage_descriptor {
    location      = "s3://${var.s3_bucket_name}/AWSLogs/${var.account_id}/CloudTrail/"
    input_format  = "org.apache.hadoop.mapred.TextInputFormat"
    output_format = "org.apache.hadoop.hive.ql.io.HiveIgnoreKeyTextOutputFormat"

    ser_de_info {
      name                  = "json"
      serialization_library = "org.openx.data.jsonserde.JsonSerDe"
      parameters = {
        "ignore.malformed.json" = "true"
      }
    }

    columns {
      name = "records"
      type = "array<struct<eventVersion:string,userIdentity:struct<type:string,principalId:string,arn:string,accountId:string,userName:string>,eventTime:string,eventSource:string,eventName:string,awsRegion:string,sourceIPAddress:string,userAgent:string,requestID:string,eventID:string,readOnly:boolean,eventType:string,managementEvent:boolean,recipientAccountId:string,eventCategory:string>>"
    }
  }
}

# ✅ Athena 쿼리 결과 저장용 S3 버킷
resource "aws_s3_bucket" "athena_results" {
  bucket        = "${var.s3_bucket_name}-athena-results"
  force_destroy = true

  tags = {
    Name = "athena-results"
  }
}

# ✅ Athena Workgroup
resource "aws_athena_workgroup" "athena_monitoring" {
  name = "athena-monitoring"

  configuration {
    enforce_workgroup_configuration    = true
    publish_cloudwatch_metrics_enabled = true

    result_configuration {
      output_location = "s3://${aws_s3_bucket.athena_results.bucket}/output/"
    }
  }
}

# ✅ Glue Crawler
resource "aws_glue_crawler" "cloudtrail" {
  name          = "cloudtrail-crawler"
  role          = aws_iam_role.glue.arn
  database_name = aws_glue_catalog_database.athena_db.name

  s3_target {
    path = "s3://${var.s3_bucket_name}/AWSLogs/${var.account_id}/CloudTrail/"
  }

  schedule = "cron(0 * * * ? *)"

  configuration = jsonencode({
    Version = 1.0
    CrawlerOutput = {
      Partitions = { AddOrUpdateBehavior = "InheritFromTable" }
    }
  })
}

# ✅ SNS Topic
resource "aws_sns_topic" "alarm_notifications" {
  name = "sns-athena-alarm"
}

resource "aws_sns_topic_subscription" "email_subscription" {
  topic_arn = aws_sns_topic.alarm_notifications.arn
  protocol  = "email"
  endpoint  = var.sns_email
}

# ✅ Lambda IAM Role
resource "aws_iam_role" "lambda" {
  name               = var.lambda_role_name
  assume_role_policy = data.aws_iam_policy_document.lambda_assume_role.json
}

data "aws_iam_policy_document" "lambda_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

# Lambda가 CloudWatch 로그 접근 가능하도록
resource "aws_iam_role_policy_attachment" "lambda_basic" {
  role       = aws_iam_role.lambda.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# Lambda가 Athena 쿼리 실행 가능하도록
resource "aws_iam_role_policy_attachment" "lambda_athena" {
  role       = aws_iam_role.lambda.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonAthenaFullAccess"
}

# Lambda가 S3 접근 가능하도록
resource "aws_iam_role_policy_attachment" "lambda_s3" {
  role       = aws_iam_role.lambda.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonS3FullAccess"
}

# Lambda가 SNS 발송 가능하도록
resource "aws_iam_role_policy_attachment" "lambda_sns" {
  role       = aws_iam_role.lambda.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSNSFullAccess"
}

# ✅ Lambda가 IAM 리소스를 수정/조회할 수 있도록 전체 접근 권한 부여 (주의 요망)
resource "aws_iam_role_policy_attachment" "lambda_iam_full" {
  role       = aws_iam_role.lambda.name
  policy_arn = "arn:aws:iam::aws:policy/IAMFullAccess"
}

# ✅ Lambda Function
resource "aws_lambda_function" "secmonitor" {
  function_name = var.lambda_function_name
  handler       = "lambda_function.lambda_handler"
  runtime       = "python3.13"
  role          = aws_iam_role.lambda.arn

  filename         = "lambda_function.zip"
  source_code_hash = filebase64sha256("lambda_function.zip")

  environment {
    variables = {
      SNS_TOPIC_ARN   = aws_sns_topic.alarm_notifications.arn
      DISCORD_WEBHOOK = var.discord_webhook_url
      ATHENA_DB       = var.athena_db
      ATHENA_TABLE    = var.athena_table
      WORKGROUP       = aws_athena_workgroup.athena_monitoring.name
      ATHENA_OUTPUT   = "s3://${aws_s3_bucket.athena_results.bucket}/output/"
    }
  }

  timeout = 60
}

# ✅ EventBridge
resource "aws_cloudwatch_event_rule" "schedule" {
  name                = var.eventbridge_rule_name
  description         = "Periodic Athena Lambda trigger"
  schedule_expression = "rate(1 hour)"
}

resource "aws_cloudwatch_event_target" "lambda" {
  rule      = aws_cloudwatch_event_rule.schedule.name
  target_id = "LambdaAthenaSecMonitor"
  arn       = aws_lambda_function.secmonitor.arn
}

resource "aws_lambda_permission" "allow_eventbridge" {
  statement_id  = "AllowExecutionFromEventBridge"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.secmonitor.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.schedule.arn
}

