########################################
# Provider 설정 (서울 리전)
########################################
provider "aws" {
  region = "ap-northeast-2" # AWS 서울 리전 사용
}

# 현재 계정 정보 (Account ID 등)를 참조하기 위해 사용
data "aws_caller_identity" "current" {}

########################################
# 1. S3 + CloudTrail 로그 저장 설정
########################################

# CloudTrail 로그를 저장할 S3 버킷 생성
resource "aws_s3_bucket" "trail_bucket" {
  bucket        = "ami-monitoring-trail-bucket" # 고유한 버킷 이름 사용
  force_destroy = true # 버킷 삭제 시 객체도 함께 삭제
}

# S3 버킷에 대한 퍼블릭 접근 차단 설정
resource "aws_s3_bucket_public_access_block" "trail_bucket_block" {
  bucket = aws_s3_bucket.trail_bucket.id

  block_public_acls       = true  # 퍼블릭 ACL 지정 차단
  block_public_policy     = true  # 퍼블릭한 버킷 정책 차단
  ignore_public_acls      = true  # 퍼블릭 ACL 있어도 무시
  restrict_public_buckets = true  # 퍼블릭 정책이 있어도 접근 거부
}

# CloudTrail이 S3에 로그를 쓸 수 있도록 정책 부여
resource "aws_s3_bucket_policy" "trail_bucket_policy" {
  bucket = aws_s3_bucket.trail_bucket.id

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Sid: "AWSCloudTrailAclCheck",
        Effect: "Allow",
        Principal: {
          Service: "cloudtrail.amazonaws.com"
        },
        Action: "s3:GetBucketAcl",
        Resource: "arn:aws:s3:::${aws_s3_bucket.trail_bucket.id}"
      },
      {
        Sid: "AWSCloudTrailWrite",
        Effect: "Allow",
        Principal: {
          Service: "cloudtrail.amazonaws.com"
        },
        Action: "s3:PutObject",
        Resource: "arn:aws:s3:::${aws_s3_bucket.trail_bucket.id}/AWSLogs/${data.aws_caller_identity.current.account_id}/*",
        Condition: {
          StringEquals: {
            "s3:x-amz-acl": "bucket-owner-full-control"
          }
        }
      }
    ]
  })
}

# CloudTrail 생성 (전 리전 로그 수집)
resource "aws_cloudtrail" "ami_trail" {
  name                          = "ami-monitoring-trail" # 트레일 이름
  s3_bucket_name                = aws_s3_bucket.trail_bucket.id # 로그 저장 버킷
  include_global_service_events = true  # IAM 등 글로벌 서비스 포함
  is_multi_region_trail         = true  # 모든 리전 이벤트 포함
  enable_logging                = true  # 로그 수집 활성화

  depends_on = [aws_s3_bucket_policy.trail_bucket_policy]
}

########################################
# 2. Lambda 함수 (Discord Webhook 알림)
########################################

# Lambda 실행 권한을 부여할 IAM Role 생성
resource "aws_iam_role" "lambda_exec_role" {
  name = "ami_alert_lambda_role"

  assume_role_policy = jsonencode({
    Version: "2012-10-17",
    Statement: [{
      Effect: "Allow",
      Action: "sts:AssumeRole",
      Principal: {
        Service: "lambda.amazonaws.com"
      }
    }]
  })
}

# Lambda에 CloudWatch 로그 기록 정책 부여
resource "aws_iam_role_policy_attachment" "lambda_basic" {
  role       = aws_iam_role.lambda_exec_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# Discord Webhook으로 알림을 보내는 Lambda 함수 생성
resource "aws_lambda_function" "discord_alert" {
  filename         = "lambda.zip" # 패키징된 Lambda 코드(zip 파일)
  function_name    = "ami_alert" # 함수 이름
  role             = aws_iam_role.lambda_exec_role.arn
  handler          = "lambda_function.lambda_handler" # Python 핸들러
  runtime          = "python3.12" # 실행 런타임
  source_code_hash = filebase64sha256("lambda.zip") # 코드 무결성 확인

  environment {
    variables = {
      HOOK_URL = var.discord_webhook_url # Discord Webhook URL 환경 변수
    }
  }
}

########################################
# 3. SNS Topic (Email + Lambda 알림 전송)
########################################

# SNS 주제 생성
resource "aws_sns_topic" "ami_topic" {
  name = "ami-change-topic"
}

# 이메일 구독자 등록 (알림 수신)
resource "aws_sns_topic_subscription" "email_sub" {
  topic_arn = aws_sns_topic.ami_topic.arn
  protocol  = "email"
  endpoint  = var.notification_email
}

# Lambda 함수 구독 등록 (알림 수신)
resource "aws_sns_topic_subscription" "lambda_sub" {
  topic_arn = aws_sns_topic.ami_topic.arn
  protocol  = "lambda"
  endpoint  = aws_lambda_function.discord_alert.arn
}

# SNS가 Lambda 함수를 호출할 수 있도록 권한 허용
resource "aws_lambda_permission" "allow_sns" {
  statement_id  = "AllowExecutionFromSNS"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.discord_alert.function_name
  principal     = "sns.amazonaws.com"
  source_arn    = aws_sns_topic.ami_topic.arn
}

# EventBridge가 SNS로 메시지 전송할 수 있도록 정책 설정
resource "aws_sns_topic_policy" "allow_eventbridge" {
  arn = aws_sns_topic.ami_topic.arn

  policy = jsonencode({
    Version: "2012-10-17",
    Statement: [{
      Sid: "AllowEventBridgePublish",
      Effect: "Allow",
      Principal: {
        Service: "events.amazonaws.com"
      },
      Action: "sns:Publish",
      Resource: aws_sns_topic.ami_topic.arn
    }]
  })
}

########################################
# 4. EventBridge 규칙 (AMI launchPermission 변경 탐지)
########################################

# AMI launchPermission 속성 변경 이벤트 탐지
resource "aws_cloudwatch_event_rule" "ami_attribute_change" {
  name        = "detect-ami-launch-permission-change"
  description = "Detect when AMI launchPermission is modified (public or shared)"

  event_pattern = jsonencode({
    "source": ["aws.ec2"], # EC2 서비스로부터 발생한 이벤트
    "detail-type": ["AWS API Call via CloudTrail"], # CloudTrail API 이벤트
    "detail": {
      "eventName": ["ModifyImageAttribute"], # AMI 속성 변경 이벤트
      "requestParameters": {
        "attributeType": ["launchPermission"] # launchPermission이 변경된 경우만
      }
    }
  })
}

# 탐지된 이벤트를 SNS로 전달
resource "aws_cloudwatch_event_target" "ami_to_sns" {
  rule      = aws_cloudwatch_event_rule.ami_attribute_change.name
  target_id = "SendToSNS"
  arn       = aws_sns_topic.ami_topic.arn
}