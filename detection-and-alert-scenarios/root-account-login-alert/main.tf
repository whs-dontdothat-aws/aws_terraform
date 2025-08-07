provider "aws" {
  region = "us-east-1"
}

# S3 Bucket for CloudTrail logs
resource "aws_s3_bucket" "cloudtrail_bucket" {
  bucket = "root-login-alert-trail-bucket"
}

resource "aws_s3_bucket_public_access_block" "block_public_access" {
  bucket = aws_s3_bucket.cloudtrail_bucket.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_policy" "cloudtrail_bucket_policy" {
  bucket = aws_s3_bucket.cloudtrail_bucket.id

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Sid       = "AWSCloudTrailAclCheck",
        Effect    = "Allow",
        Principal = { Service = "cloudtrail.amazonaws.com" },
        Action    = "s3:GetBucketAcl",
        Resource  = "arn:aws:s3:::${aws_s3_bucket.cloudtrail_bucket.id}"
      },
      {
        Sid       = "AWSCloudTrailWrite",
        Effect    = "Allow",
        Principal = { Service = "cloudtrail.amazonaws.com" },
        Action    = "s3:PutObject",
        Resource  = "arn:aws:s3:::${aws_s3_bucket.cloudtrail_bucket.id}/AWSLogs/${data.aws_caller_identity.current.account_id}/*",
        Condition = {
          StringEquals = {
            "s3:x-amz-acl" = "bucket-owner-full-control"
          }
        }
      }
    ]
  })
}

data "aws_caller_identity" "current" {}


# CloudTrail 설정
resource "aws_cloudtrail" "root_login_trail" {
  name                          = "root-console-login-alarm"
  s3_bucket_name                = aws_s3_bucket.cloudtrail_bucket.id
  include_global_service_events = true
  is_multi_region_trail         = true
  enable_logging                = true
}

# Lambda 실행 역할
resource "aws_iam_role" "lambda_exec_role" {
  name = "lambda_root_login_exec_role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Action = "sts:AssumeRole",
      Effect = "Allow",
      Principal = {
        Service = "lambda.amazonaws.com"
      }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_basic" {
  role       = aws_iam_role.lambda_exec_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# Lambda 함수 정의
resource "aws_lambda_function" "discord_alert" {
  filename         = "lambda.zip"
  function_name    = "root_login_notify_discord"
  role             = aws_iam_role.lambda_exec_role.arn
  handler          = "lambda_function.lambda_handler"
  runtime          = "python3.13"
  source_code_hash = filebase64sha256("lambda.zip")
  environment {
    variables = {
      HOOK_URL = var.discord_webhook_url
    }
  }
}

# SNS Topic & Email 구독
resource "aws_sns_topic" "root_login_email_topic" {
  name = "root-console-login-email"
}

resource "aws_sns_topic_subscription" "email_subscriber" {
  topic_arn = aws_sns_topic.root_login_email_topic.arn
  protocol  = "email"
  endpoint  = var.notification_email
}

# EventBridge 규칙
resource "aws_cloudwatch_event_rule" "root_login_rule" {
  name        = "root-login-pattern"
  description = "Detect root login and trigger Lambda & SNS"
  event_pattern = jsonencode({
    "detail-type": ["AWS Console Sign In via CloudTrail"],
    "detail": {
      "userIdentity": {
        "type": ["Root"]
      },
      "eventName": ["ConsoleLogin"]
    }
  })
}

# Lambda와 연결
resource "aws_cloudwatch_event_target" "send_to_lambda" {
  rule      = aws_cloudwatch_event_rule.root_login_rule.name
  target_id = "sendToLambda"
  arn       = aws_lambda_function.discord_alert.arn
}

resource "aws_lambda_permission" "allow_eventbridge" {
  statement_id  = "AllowExecutionFromEventBridge"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.discord_alert.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.root_login_rule.arn
}

# SNS와 연결
resource "aws_cloudwatch_event_target" "send_to_sns" {
  rule      = aws_cloudwatch_event_rule.root_login_rule.name
  target_id = "sendToSNS"
  arn       = aws_sns_topic.root_login_email_topic.arn
}

resource "aws_sns_topic_policy" "allow_eventbridge" {
  arn    = aws_sns_topic.root_login_email_topic.arn
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Sid       = "AllowEventBridgePublish",
        Effect    = "Allow",
        Principal = { Service = "events.amazonaws.com" },
        Action    = "sns:Publish",
        Resource  = aws_sns_topic.root_login_email_topic.arn
      }
    ]
  })
}