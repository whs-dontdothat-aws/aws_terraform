#--------------------------------------
# Provider 설정: AWS 리전
#--------------------------------------
provider "aws" {
  region = "ap-northeast-2" # 서울 리전
}

#--------------------------------------
# S3 객체: 초기 dummy 악성 IP 목록 파일
#--------------------------------------
resource "aws_s3_object" "dummy_threat_file" {
  bucket       = aws_s3_bucket.ip_list_bucket.id
  key          = "threat/malicious-ip-list.txt"
  content      = "127.0.0.1"  # 초기값으로 무해한 IP 한 줄 (루프백 주소)
  content_type = "text/plain"
}

#--------------------------------------
# S3 버킷 정책: GuardDuty가 악성 IP 목록 파일을 읽을 수 있도록 허용
#--------------------------------------
resource "aws_s3_bucket_policy" "allow_guardduty_getobject" {
  # 정책을 적용할 대상 버킷
  bucket = aws_s3_bucket.ip_list_bucket.id

  # S3 버킷에 적용할 정책 정의
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Sid       = "AllowGuardDutyGetObject",   # 정책 식별자 (선택적)
        Effect    = "Allow",                     # 허용 정책
        Principal = {
          Service = "guardduty.amazonaws.com"    # GuardDuty 서비스에게 허용
        },
        Action    = "s3:GetObject",              # 객체 읽기 권한
        Resource  = "arn:aws:s3:::s3-ip-list-bucket-tf/threat/malicious-ip-list.txt"  # 대상 파일 경로
      }
    ]
  })
}

#--------------------------------------
# S3 버킷: 악성 IP 목록을 저장할 위치
#--------------------------------------
resource "aws_s3_bucket" "ip_list_bucket" {
  bucket        = "s3-ip-list-bucket-tf"  # 고유한 버킷 이름 필수
  force_destroy = true  # terraform destroy 시 객체까지 삭제
}

#--------------------------------------
# GuardDuty ThreatIntelSet: 악성 IP 등록을 하기위해
# S3에 파일이 업로드되기를 기다리기 위한 시간 지연을 위한 코드
#--------------------------------------
resource "time_sleep" "wait_for_s3_upload" {
  create_duration = "30s"
}

#--------------------------------------
# Lambda: 외부 악성 IP를 가져와 S3에 저장
#--------------------------------------
resource "aws_lambda_function" "update_ip_list" {
  function_name    = "lambda-update-ip-list-tf"
  filename         = "update_ip_list.zip" # 사전에 압축된 lambda 코드
  source_code_hash = filebase64sha256("update_ip_list.zip")
  handler          = "lambda_function.lambda_handler"
  runtime          = "python3.13"
  role             = aws_iam_role.lambda_update_ip_list_role.arn
  timeout          = 30
}

#--------------------------------------
# EventBridge Rule: Lambda 주기 실행 (매일 1회)
#--------------------------------------
resource "aws_cloudwatch_event_rule" "lambda_schedule" {
  name                = "eb-execute-lambda-tf"
  schedule_expression = "rate(1 day)"
}

#--------------------------------------
# EventBridge → Lambda 연결
#--------------------------------------
resource "aws_cloudwatch_event_target" "lambda_target" {
  rule      = aws_cloudwatch_event_rule.lambda_schedule.name
  target_id = "lambda"
  arn       = aws_lambda_function.update_ip_list.arn
}

#--------------------------------------
# Lambda가 EventBridge에서 호출되도록 권한 부여
#--------------------------------------
resource "aws_lambda_permission" "allow_eventbridge" {
  statement_id  = "AllowExecutionFromEventBridge"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.update_ip_list.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.lambda_schedule.arn
}

#--------------------------------------
# GuardDuty ThreatIntelSet: 악성 IP 등록
#--------------------------------------
resource "aws_guardduty_threatintelset" "malicious_ip_list" {
  activate     = true
  detector_id  = var.guardduty_detector_id
  format       = "TXT"
  location = "https://${aws_s3_bucket.ip_list_bucket.bucket}.s3.ap-northeast-2.amazonaws.com/threat/malicious-ip-list.txt"
  name         = "gd-threat-malicious-ip-list-tf"
  
#--------------------------------------
# 이 리소스는 S3에 파일이 업로드된 이후에 만들어져야 하므로 명시적 종속성 선언
#--------------------------------------
  depends_on = [
    aws_lambda_function.update_ip_list,
    aws_iam_role.lambda_update_ip_list_role,
    aws_iam_role_policy.lambda_update_ip_list_policy,
    aws_s3_bucket.ip_list_bucket,
    aws_s3_object.dummy_threat_file,
    time_sleep.wait_for_s3_upload
  ]
}

#--------------------------------------
# SNS: 이메일 알림 전송
#--------------------------------------
resource "aws_sns_topic" "threat_ip_alarm" {
  name = "sns-threat-ip-alarm-tf"
}

resource "aws_sns_topic_subscription" "email" {
  topic_arn = aws_sns_topic.threat_ip_alarm.arn
  protocol  = "email"
  endpoint  = var.notification_email  # 예: "user@example.com"
}

#--------------------------------------
# Lambda: Discord 알림 + EC2 대응 (스냅샷, 중단)
#--------------------------------------
resource "aws_lambda_function" "discord_and_ec2_alarm" {
  function_name    = "lambda-discord-and-ec2-alarm-tf"
  filename         = "discord_and_ec2_alarm.zip"
  source_code_hash = filebase64sha256("discord_and_ec2_alarm.zip")
  handler          = "lambda_function.lambda_handler"
  runtime          = "python3.13"
  role             = aws_iam_role.discord_and_ec2_alarm_role.arn
  timeout          = 60

  environment {
    variables = {
      DISCORD_WEBHOOK_URL = var.discord_webhook_url
    }
  }
}

#--------------------------------------
# GuardDuty 이벤트 감지 설정
#--------------------------------------
resource "aws_cloudwatch_event_rule" "guardduty_finding" {
  name        = "eb-detect-guardduty-tf"
  description = "Detect GuardDuty findings for custom threat list"
  event_pattern = <<EOF
{
  "source": ["aws.guardduty"],
  "detail-type": ["GuardDuty Finding"],
  "detail": {
    "type": ["UnauthorizedAccess:EC2/MaliciousIPCaller.Custom"]
  }
}
EOF
}

#--------------------------------------
# EventBridge → SNS 연결 (이메일 알림)
#--------------------------------------
resource "aws_cloudwatch_event_target" "sns_alarm" {
  rule      = aws_cloudwatch_event_rule.guardduty_finding.name # 연결할 EventBridge 규칙 이름
  target_id = "sns"  # 타깃 ID (식별용)
  arn       = aws_sns_topic.threat_ip_alarm.arn # 대상 SNS 주제 ARN
  role_arn  = aws_iam_role.eventbridge_invoke_sns_role.arn
  # 핵심: EventBridge가 SNS에 Publish할 수 있도록 실행 역할 지정
}

#--------------------------------------
# EventBridge → Lambda 연결 (디스코드 + EC2 대응)
#--------------------------------------
resource "aws_cloudwatch_event_target" "discord_and_ec2_alarm" {
  rule      = aws_cloudwatch_event_rule.guardduty_finding.name
  target_id = "discord_and_ec2_alarm"
  arn       = aws_lambda_function.discord_and_ec2_alarm.arn
}

#--------------------------------------
# EventBridge가 Lambda를 실행할 수 있도록 권한 부여
#--------------------------------------
resource "aws_lambda_permission" "allow_eventbridge_discord_and_ec2_alarm" {
  statement_id  = "AllowExecutionFromEventBridgeDiscord"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.discord_and_ec2_alarm.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.guardduty_finding.arn
}
