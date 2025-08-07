#---------------------------------------------------------------------------
# 1. PROVIDER ─ AWS 리전 설정 (버지니아)
#---------------------------------------------------------------------------
provider "aws" {
  region = "us-east-1"
}

#---------------------------------------------------------------------------
# 2. CloudTrail 설정(이미 리전에 추적 존재한다면 이 부분 생략)
#---------------------------------------------------------------------------

# CloudTrail 로그를 저장할 S3 버킷 생성
resource "aws_s3_bucket" "cloudtrail_bucket" {
  bucket = "iam-user-event-alarm-bucket" # 버킷 이름
  force_destroy = true # destroy 할 때 강제로 삭제하게함 (로그 비우고 삭제)
}

# 생성한 S3 버킷에 대한 퍼블릭 액세스 차단
resource "aws_s3_bucket_public_access_block" "block_public_access" {
  bucket = aws_s3_bucket.cloudtrail_bucket.id

  block_public_acls       = true # 퍼블릭 ACL 지정 차단
  block_public_policy     = true # 퍼블릭한 버킷 정책 차단
  ignore_public_acls      = true # 퍼블릭 ACL 있어도 무시
  restrict_public_buckets = true # 퍼블릭 정책이 있어도 거부
}

# CloudTrail 서비스가 로그 기록을 위한 S3 버킷에 접근 허용
resource "aws_s3_bucket_policy" "cloudtrail_bucket_policy" {
  bucket = aws_s3_bucket.cloudtrail_bucket.id

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [ # CloudTrail이 ACL을 읽는 권한 필요
      {
        Sid       = "AWSCloudTrailAclCheck",
        Effect    = "Allow",
        Principal = { Service = "cloudtrail.amazonaws.com" },
        Action    = "s3:GetBucketAcl",
        Resource  = "arn:aws:s3:::${aws_s3_bucket.cloudtrail_bucket.id}"
      },
      { # CloudTrail이 로그 객체를 업로드 할 수 있도록 설정
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

# 현재 사용중인 계정 ID 가져옴
data "aws_caller_identity" "current" {}


# CloudTrail 추적 생성
resource "aws_cloudtrail" "iam_event_trail" {
  name                          = aws_s3_bucket.cloudtrail_bucket.bucket # Trail 이름름
  s3_bucket_name                = aws_s3_bucket.cloudtrail_bucket.id
  include_global_service_events = true
  is_multi_region_trail         = true
  enable_logging                = true
}

#---------------------------------------------------------------------------
# 3. Lambda 설정
#---------------------------------------------------------------------------

# Lambda 실행을 위한 IAM 역할 생성
resource "aws_iam_role" "lambda_exec_role" {
  name = "lambda_iam_event_exec_role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Action = "sts:AssumeRole", # 역할 위임받는 데 필요한 권한 부여
      Effect = "Allow",
      Principal = {
        Service = "lambda.amazonaws.com"
      }
    }]
  })
}

# Lambda 실행 IAM 역할에 정책 연결
resource "aws_iam_role_policy_attachment" "lambda_basic" {
  role       = aws_iam_role.lambda_exec_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}


# Lambda 함수 정의
resource "aws_lambda_function" "discord_alert" {
  filename         = "lambda_function.zip"
  function_name    = "iam_user_event_discord"
  role             = aws_iam_role.lambda_exec_role.arn
  handler          = "lambda_function.lambda_handler"
  runtime          = "python3.13"
  source_code_hash = filebase64sha256("lambda_function.zip")
  environment {
    variables = {
      HOOK_URL = var.discord_webhook_url
    }
  }
}


#---------------------------------------------------------------------------
# 4. SNS Topic 및 Email, Lambda 구독 설정
#---------------------------------------------------------------------------

# SNS 생성
resource "aws_sns_topic" "iam_user_event_topic" {
  name = "iam-user-event-topic"
}

# 이메일 구독 생성
resource "aws_sns_topic_subscription" "email_subscriber" {
  topic_arn = aws_sns_topic.iam_user_event_topic.arn
  protocol  = "email"
  endpoint  = var.notification_email
}

# Lambda 구독 생성
resource "aws_sns_topic_subscription" "lambda_subscriber" {
  topic_arn = aws_sns_topic.iam_user_event_topic.arn
  protocol  = "lambda"
  endpoint  = aws_lambda_function.discord_alert.arn
}

# SNS가 Lambda 호출할 수 있도록 권한 부여
resource "aws_lambda_permission" "allow_sns_invoke" {
  statement_id = "AllowExecutionFromSNS"
  action = "lambda:InvokeFunction"
  function_name = aws_lambda_function.discord_alert.function_name
  principal = "sns.amazonaws.com"
  source_arn = aws_sns_topic.iam_user_event_topic.arn
}

#---------------------------------------------------------------------------
# 5. EventBridge 설정
#---------------------------------------------------------------------------

# EventBridge 규칙 생성 : IAM User 생성, 삭제 탐지
resource "aws_cloudwatch_event_rule" "iam_user_event_pattern" {
  name        = "iam-user-event-pattern"
  description = "Detect IAM User Event and trigger Lambda & SNS"
  event_pattern = jsonencode({
    "source": ["aws.iam"],
    "detail-type": ["AWS API Call via CloudTrail"],
    "detail": {
      "eventSource": ["iam.amazonaws.com"],
      "eventName": ["CreateUser", "DeleteUser"]
    }
  })
}

# EventBridge 규칙의 타겟으로 SNS 주 연결
resource "aws_cloudwatch_event_target" "send_to_sns" {
  rule      = aws_cloudwatch_event_rule.iam_user_event_pattern.name
  target_id = "sendToSNS"
  arn       = aws_sns_topic.iam_user_event_topic.arn
}

# EventBridge에 SNS 호출 권한을 부여
resource "aws_sns_topic_policy" "allow_eventbridge" {
  arn    = aws_sns_topic.iam_user_event_topic.arn
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Sid       = "AllowEventBridgePublish",
        Effect    = "Allow",
        Principal = { Service = "events.amazonaws.com" },
        Action    = "sns:Publish",
        Resource  = aws_sns_topic.iam_user_event_topic.arn
      }
    ]
  })
}