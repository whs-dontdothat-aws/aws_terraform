provider "aws" {
  region = "ap-northeast-2"
}

data "aws_caller_identity" "current" {}

####################################################
# 1. S3 Bucket (CloudTrail Logs)
####################################################

resource "aws_s3_bucket" "cloudtrail_logs" {
  bucket = "s3-cloudtrail-monitor"

  versioning {
    enabled = true
  }

  server_side_encryption_configuration {
    rule {
      apply_server_side_encryption_by_default {
        sse_algorithm = "AES256"
      }
    }
  }

  tags = {
    Name = "CloudTrailLogs"
  }
}
resource "aws_s3_bucket_policy" "cloudtrail_policy" {
  bucket = aws_s3_bucket.cloudtrail_logs.id

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Sid    = "AWSCloudTrailAclCheck20150319",
        Effect = "Allow",
        Principal = {
          Service = "cloudtrail.amazonaws.com"
        },
        Action   = "s3:GetBucketAcl",
        Resource = aws_s3_bucket.cloudtrail_logs.arn
      },
      {
        Sid    = "AWSCloudTrailWrite20150319",
        Effect = "Allow",
        Principal = {
          Service = "cloudtrail.amazonaws.com"
        },
        Action   = "s3:PutObject",
        Resource = "${aws_s3_bucket.cloudtrail_logs.arn}/AWSLogs/${data.aws_caller_identity.current.account_id}/*",
        Condition = {
          StringEquals = {
            "s3:x-amz-acl" : "bucket-owner-full-control"
          }
        }
      }
    ]
  })
}

####################################################
# 2. CloudTrail Trail
####################################################

resource "aws_cloudtrail" "ct_trail" {
  name                          = "ct-trail-monitor"
  s3_bucket_name                = aws_s3_bucket.cloudtrail_logs.id
  include_global_service_events = true
  is_multi_region_trail         = true
  enable_log_file_validation    = true

  event_selector {
    read_write_type           = "All"
    include_management_events = true
  }

  tags = {
    Name = "ct-trail-monitor"
  }


  depends_on = [aws_s3_bucket_policy.cloudtrail_policy]
}
####################################################
# 3. SNS Alarm Topic + Email Subscription
####################################################

resource "aws_sns_topic" "cloudtrail_alarm" {
  name = "sns-cloudtrail-alarm"
}

resource "aws_sns_topic_subscription" "email_sub" {
  topic_arn = aws_sns_topic.cloudtrail_alarm.arn
  protocol  = "email"
  endpoint  = var.email_address
}

####################################################
# 4. EventBridge Rule → SNS Trigger
####################################################

resource "aws_cloudwatch_event_rule" "ct_eventbridge_rule" {
  name        = "eventbridge-ct-detect"
  description = "Detect CloudTrail Stop/Delete/Update events"
  event_pattern = jsonencode({
    source       = ["aws.cloudtrail"],
    "detail-type" = ["AWS API Call via CloudTrail"],
    detail       = {
      eventSource = ["cloudtrail.amazonaws.com"],
      eventName   = ["StopLogging", "DeleteTrail", "UpdateTrail", "PutEventSelectors"]
    }
  })
}

resource "aws_cloudwatch_event_target" "sns_target" {
  rule      = aws_cloudwatch_event_rule.ct_eventbridge_rule.name
  target_id = "SendToSNS"
  arn       = aws_sns_topic.cloudtrail_alarm.arn
}

####################################################
# 5. Lambda Function (Discord Notification)
####################################################

resource "aws_lambda_function" "discord_alert" {
  function_name = "lambda-ct-detect-alarm"
  filename      = "${path.module}/lambda.zip"
  handler       = "lambda_function.lambda_handler"
  runtime       = "python3.13"
  role          = aws_iam_role.lambda_exec.arn

  environment {
    variables = {
      DISCORD_WEBHOOK_URL = var.discord_webhook_url
    }
  }

  depends_on = [aws_iam_role_policy_attachment.lambda_basic]
}

####################################################
# 6. IAM for Lambda Execution
####################################################

resource "aws_iam_role" "lambda_exec" {
  name = "lambda-ct-detect-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = "sts:AssumeRole",
        Effect = "Allow",
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_basic" {
  role       = aws_iam_role.lambda_exec.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

####################################################
# 7. SNS → Lambda Subscription + Permissions
####################################################

resource "aws_sns_topic_subscription" "lambda_sub" {
  topic_arn = aws_sns_topic.cloudtrail_alarm.arn
  protocol  = "lambda"
  endpoint  = aws_lambda_function.discord_alert.arn
}

resource "aws_lambda_permission" "allow_sns" {
  statement_id  = "AllowExecutionFromSNS"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.discord_alert.function_name
  principal     = "sns.amazonaws.com"
  source_arn    = aws_sns_topic.cloudtrail_alarm.arn
}