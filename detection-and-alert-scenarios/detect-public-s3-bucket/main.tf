###############################################################################
#  PROVIDER ─ AWS 리전 설정
###############################################################################
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = "ap-northeast-2"
}

###############################################################################
#  현재 AWS 계정 정보
###############################################################################
data "aws_caller_identity" "current" {}

###############################################################################
#  S3 버킷 ─ AWS Config 로그 저장
###############################################################################
resource "aws_s3_bucket" "config_bucket" {
  bucket = "s3-public-bucket-config"
}

resource "aws_s3_bucket_public_access_block" "config_bucket_block" {
  bucket = aws_s3_bucket.config_bucket.id

  block_public_acls       = true
  ignore_public_acls      = true
  block_public_policy     = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_policy" "config_bucket_policy" {
  bucket = aws_s3_bucket.config_bucket.id

  policy = jsonencode({
    Version   = "2012-10-17"
    Statement = [
      {
        Sid    = "AWSConfigBucketPermissionsCheck"
        Effect = "Allow"
        Principal = { Service = "config.amazonaws.com" }
        Action   = "s3:GetBucketAcl"
        Resource = aws_s3_bucket.config_bucket.arn
        Condition = {
          StringEquals = {
            "AWS:SourceAccount" = data.aws_caller_identity.current.account_id
          }
        }
      },
      {
        Sid    = "AWSConfigBucketExistenceCheck"
        Effect = "Allow"
        Principal = { Service = "config.amazonaws.com" }
        Action   = "s3:ListBucket"
        Resource = aws_s3_bucket.config_bucket.arn
        Condition = {
          StringEquals = {
            "AWS:SourceAccount" = data.aws_caller_identity.current.account_id
          }
        }
      },
      {
        Sid    = "AWSConfigBucketDelivery"
        Effect = "Allow"
        Principal = { Service = "config.amazonaws.com" }
        Action   = "s3:PutObject"
        Resource = "${aws_s3_bucket.config_bucket.arn}/*"
        Condition = {
          StringEquals = {
            "s3:x-amz-acl"      = "bucket-owner-full-control"
            "AWS:SourceAccount" = data.aws_caller_identity.current.account_id
          }
        }
      },
      {
        Sid    = "AWSConfigBucketGetObject"
        Effect = "Allow"
        Principal = { Service = "config.amazonaws.com" }
        Action   = "s3:GetObject"
        Resource = "${aws_s3_bucket.config_bucket.arn}/*"
        Condition = {
          StringEquals = {
            "AWS:SourceAccount" = data.aws_caller_identity.current.account_id
          }
        }
      }
    ]
  })

  depends_on = [aws_s3_bucket_public_access_block.config_bucket_block]
}

###############################################################################
#  IAM 역할 ─ AWS Config Recorder
###############################################################################
resource "aws_iam_role" "config_service_role" {
  name = "AWSConfigServiceRole"

  assume_role_policy = jsonencode({
    Version   = "2012-10-17",
    Statement = [{
      Effect    = "Allow",
      Principal = { Service = "config.amazonaws.com" },
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "config_policy_attach" {
  role       = aws_iam_role.config_service_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWS_ConfigRole"
}

###############################################################################
#  AWS Config ─ Recorder / Delivery Channel
###############################################################################
resource "aws_config_configuration_recorder" "recorder" {
  name     = "default"
  role_arn = aws_iam_role.config_service_role.arn

  recording_group {
    all_supported                 = true
    include_global_resource_types = true
  }

  depends_on = [aws_s3_bucket_policy.config_bucket_policy]
}

resource "aws_config_delivery_channel" "main" {
  name           = "default"
  s3_bucket_name = aws_s3_bucket.config_bucket.id

  depends_on = [aws_config_configuration_recorder.recorder]
}

resource "aws_config_configuration_recorder_status" "recorder_status" {
  name       = aws_config_configuration_recorder.recorder.name
  is_enabled = true

  depends_on = [aws_config_delivery_channel.main]
}

###############################################################################
#  AWS Config 규칙 ─ 퍼블릭 읽기/쓰기 금지
###############################################################################
resource "aws_config_config_rule" "s3_public_read_prohibited" {
  name        = "s3-bucket-public-read-prohibited"
  description = "S3 버킷 퍼블릭 읽기 권한 금지"

  scope {
    compliance_resource_types = ["AWS::S3::Bucket"]
  }

  source {
    owner             = "AWS"
    source_identifier = "S3_BUCKET_PUBLIC_READ_PROHIBITED"
  }

  depends_on = [aws_config_configuration_recorder.recorder]
}

resource "aws_config_config_rule" "s3_public_write_prohibited" {
  name        = "s3-bucket-public-write-prohibited"
  description = "S3 버킷 퍼블릭 쓰기 권한 금지"

  scope {
    compliance_resource_types = ["AWS::S3::Bucket"]
  }

  source {
    owner             = "AWS"
    source_identifier = "S3_BUCKET_PUBLIC_WRITE_PROHIBITED"
  }

  depends_on = [aws_config_configuration_recorder.recorder]
}

###############################################################################
#  IAM 역할 ─ Lambda 실행
###############################################################################
resource "aws_iam_role" "lambda_exec_role" {
  name = "ConfigRuleNotifierLambdaRole"

  assume_role_policy = jsonencode({
    Version   = "2012-10-17",
    Statement = [{
      Effect    = "Allow",
      Principal = { Service = "lambda.amazonaws.com" },
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_logs_policy" {
  role       = aws_iam_role.lambda_exec_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

###############################################################################
#  Lambda 함수 ─ Discord 웹훅
###############################################################################
resource "aws_lambda_function" "discord_notifier" {
  function_name    = "Discord"
  filename         = "function.zip"
  source_code_hash = filebase64sha256("function.zip")
  runtime          = "python3.13"
  handler          = "lambda_function.lambda_handler"
  role             = aws_iam_role.lambda_exec_role.arn

  environment {
    variables = {
      DISCORD_WEBHOOK_URL = var.discord_webhook_url
    }
  }
}

###############################################################################
#  EventBridge 규칙 ─ NON_COMPLIANT
###############################################################################
resource "aws_cloudwatch_event_rule" "config_noncompliant_rule" {
  name        = "public-event-rule"
  description = "AWS Config 규칙 NON_COMPLIANT 시 트리거"

  event_pattern = jsonencode({
    source        = ["aws.config"],
    "detail-type" = ["Config Rules Compliance Change"],
    detail        = {
      configRuleName = [
        aws_config_config_rule.s3_public_read_prohibited.name,
        aws_config_config_rule.s3_public_write_prohibited.name
      ],
      messageType         = ["ComplianceChangeNotification"],
      newEvaluationResult = { complianceType = ["NON_COMPLIANT"] }
    }
  })
}

###############################################################################
#  EventBridge 대상 ─ Lambda (Discord)
###############################################################################
resource "aws_cloudwatch_event_target" "config_rule_lambda_target" {
  rule      = aws_cloudwatch_event_rule.config_noncompliant_rule.name
  target_id = "DiscordNotifierLambda"
  arn       = aws_lambda_function.discord_notifier.arn
}

resource "aws_lambda_permission" "allow_eventbridge" {
  function_name = aws_lambda_function.discord_notifier.function_name
  action        = "lambda:InvokeFunction"
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.config_noncompliant_rule.arn
}

###############################################################################
#  SNS ─ 이메일 알림 + EventBridge 권한
###############################################################################
resource "aws_sns_topic" "config_alert_email" {
  name         = "Email"
  display_name = "AWS Config Alerts Email"
}

# EventBridge가 토픽으로 Publish 할 수 있도록 정책 부여
resource "aws_sns_topic_policy" "allow_eventbridge_publish" {
  arn = aws_sns_topic.config_alert_email.arn

  policy = jsonencode({
    Version   = "2012-10-17",
    Statement = [
      {
        Sid       = "AllowEventBridgePublish"
        Effect    = "Allow"
        Principal = { Service = "events.amazonaws.com" }
        Action    = "sns:Publish"
        Resource  = aws_sns_topic.config_alert_email.arn
      }
    ]
  })
}

resource "aws_sns_topic_subscription" "config_alert_email_sub" {
  topic_arn = aws_sns_topic.config_alert_email.arn
  protocol  = "email"
  endpoint  = var.notification_email
}

resource "aws_cloudwatch_event_target" "config_rule_sns_target" {
  rule      = aws_cloudwatch_event_rule.config_noncompliant_rule.name
  target_id = "EmailAlertTopic"
  arn       = aws_sns_topic.config_alert_email.arn
}