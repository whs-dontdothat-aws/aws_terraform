#---------------------------------------------------------------------------
# 1. PROVIDER ─ AWS 리전 설정 (서울)
#--------------------------------------------------------------------------
provider "aws" {
  region = "ap-northeast-2" # 서울 리전 사용
}

#---------------------------------------------------------------------------
# 2. CloudTrail 설정(이미 리전에 추적 존재한다면 이 부분 생략)
#---------------------------------------------------------------------------

# 현재 AWS 계정 정보 조회 (account_id 등 활용 가능)
data "aws_caller_identity" "current" {}

# CloudTrail 로그를 저장할 S3 버킷 생성
resource "aws_s3_bucket" "trail_bucket" {
  bucket = "log-group-trail-bucket"
  force_destroy = true # 버킷 비워진 후 삭제 허용
}

# 생성한 S3 버킷에 대한 퍼블릭 액세스 차단
resource "aws_s3_bucket_public_access_block" "trail_bucket_block" {
  bucket                  = aws_s3_bucket.trail_bucket.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# CloudTrail 서비스가 로그 기록을 위한 S3 버킷에 접근 허용
resource "aws_s3_bucket_policy" "trail_bucket_policy" {
  bucket = aws_s3_bucket.trail_bucket.id

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Sid    = "AWSCloudTrailAclCheck",
        Effect = "Allow",
        Principal = {
          Service = "cloudtrail.amazonaws.com"
        },
        Action   = "s3:GetBucketAcl",
        Resource = "arn:aws:s3:::${aws_s3_bucket.trail_bucket.id}"
      },
      {
        Sid    = "AWSCloudTrailWrite",
        Effect = "Allow",
        Principal = {
          Service = "cloudtrail.amazonaws.com"
        },
        Action   = "s3:PutObject",
        Resource = "arn:aws:s3:::${aws_s3_bucket.trail_bucket.id}/AWSLogs/${data.aws_caller_identity.current.account_id}/*",
        Condition = {
          StringEquals = {
            "s3:x-amz-acl" = "bucket-owner-full-control"
          }
        }
      }
    ]
  })
}

# CloudTrail 트레일 생성 (모든 리전에서 이벤트 수집)
resource "aws_cloudtrail" "log_group_trail" {
  name                          = "log-group-monitor"
  s3_bucket_name                = aws_s3_bucket.trail_bucket.id
  include_global_service_events = true # 글로벌 서비스 이벤트 포함
  is_multi_region_trail         = true # 다중 리전 이벤트 포함
  enable_logging                = true # 로그 수집 활성화

  depends_on = [
    aws_s3_bucket_policy.trail_bucket_policy
  ]
}

#---------------------------------------------------------------------------
# 3. Lambda 설정
#---------------------------------------------------------------------------

# Lambda 실행을 위한 IAM 역할 생성
resource "aws_iam_role" "lambda_exec_role" {
  name = "log_group_alert_lambda_role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Effect = "Allow",
      Action = "sts:AssumeRole",
      Principal = {
        Service = "lambda.amazonaws.com"
      }
    }]
  })
}


# Lambda Role 에 AWSLambdaBasicExecutionRole 정책 연결 (CloudWatch 로그 기록 가능)
resource "aws_iam_role_policy_attachment" "lambda_basic" {
  role       = aws_iam_role.lambda_exec_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}


# Discord Webhook으로 알림을 보내는 Lambda 함수 생성
resource "aws_lambda_function" "discord_alert" {
  filename         = "lambda.zip" # 패키징된 코드 zip 파일
  function_name    = "log_group_alert"
  role             = aws_iam_role.lambda_exec_role.arn
  handler          = "lambda_function.lambda_handler" # Python 핸들러 경로
  runtime          = "python3.12"
  source_code_hash = filebase64sha256("lambda.zip") # 코드 변경 감지용

  environment {
    variables = {
      HOOK_URL = var.discord_webhook_url # Discord Webhook URL 환경변수
    }
  }
}

#---------------------------------------------------------------------------
# 4. SNS Topic 및 Email, Lambda 구독 설정
#---------------------------------------------------------------------------

# SNS 생성
resource "aws_sns_topic" "log_group_topic" {
  name = "log_group_event"
}

# 이메일 구독 생성
resource "aws_sns_topic_subscription" "email_sub" {
  topic_arn = aws_sns_topic.log_group_topic.arn
  protocol  = "email"
  endpoint  = var.notification_email
}

# Lambda 구독 생성
resource "aws_sns_topic_subscription" "lambda_sub" {
  topic_arn = aws_sns_topic.log_group_topic.arn
  protocol  = "lambda"
  endpoint  = aws_lambda_function.discord_alert.arn
}

# SNS가 Lambda 호출할 수 있도록 권한 부여
resource "aws_lambda_permission" "allow_sns_invoke" {
  statement_id  = "AllowSNSInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.discord_alert.function_name
  principal     = "sns.amazonaws.com"
  source_arn    = aws_sns_topic.log_group_topic.arn
}

#---------------------------------------------------------------------------
# 5. EventBridge 설정
#---------------------------------------------------------------------------

# EventBridge 규칙 생성 : IAM User 생성, 삭제 탐지
resource "aws_sns_topic_policy" "allow_eventbridge_publish" {
  arn = aws_sns_topic.log_group_topic.arn

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Sid       = "AllowEventBridgePublish",
      Effect    = "Allow",
      Principal = { Service = "events.amazonaws.com" },
      Action    = "sns:Publish",
      Resource  = aws_sns_topic.log_group_topic.arn
    }]
  })
}

# EventBridge 규칙의 타겟으로 SNS 주 연결
resource "aws_cloudwatch_event_rule" "log_group_change_rule" {
  name        = "detect-log-group-change"
  description = "Detect CloudWatch LogGroup deletion or configuration changes"

  event_pattern = jsonencode({
    "source" : ["aws.logs"], # 로그 서비스에서 발생한 이벤트
    "detail-type" : ["AWS API Call via CloudTrail"], # API 호출 이벤트
    "detail" : {
      "eventSource" : ["logs.amazonaws.com"], # CloudWatch Logs API 호출
      "eventName" : [ # 감지할 API 이벤트 목록
        "DeleteLogGroup",           # 로그 그룹 삭제
        "PutRetentionPolicy",       # 보존 정책 변경
        "DeleteSubscriptionFilter", # Subscription 필터 삭제
        "PutSubscriptionFilter",    # Subscription 필터 추가/변경
        "DeleteResourcePolicy",     # 리소스 정책 삭제
        "PutResourcePolicy"         # 리소스 정책 추가/변경
      ]
    }
  })
}


# EventBridge 규칙의 타겟으로 SNS 주 연결
resource "aws_cloudwatch_event_target" "send_to_sns" {
  rule      = aws_cloudwatch_event_rule.log_group_change_rule.name
  target_id = "snsTarget"
  arn       = aws_sns_topic.log_group_topic.arn
}
