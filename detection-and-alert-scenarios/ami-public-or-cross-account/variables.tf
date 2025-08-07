# variables.tf
# Discord Webhook URL을 저장할 변수
# 이 URL은 Lambda 함수의 환경변수로 전달되어 알림 전송에 사용됨
variable "discord_webhook_url" {
  description = "Discord Webhook URL for Lambda environment variable"
  type        = string
  sensitive   = true  # 터미널 출력이나 로그에 표시되지 않도록 민감 정보로 처리
}

# SNS 이메일 구독자 주소를 저장할 변수
# 이 주소로 AMI 변경 탐지 시 이메일 알림이 전송됨
variable "notification_email" {
  description = "Email address to subscribe to SNS topic"
  type        = string
}