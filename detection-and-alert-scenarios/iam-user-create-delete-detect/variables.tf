# 해당 파일에서는 변수를 여기다가 모두 선언
# terraform 실행 시 terraform.tfvars에 선언된 값을 바탕으로 값이 들어감

# Discord Webhook 주소를 입력받기 위한 변수
variable "discord_webhook_url" {
  description = "Discord Webhook URL"
  type        = string
}

# 이메일 수신자를 입력받기 위한 변수
variable "notification_email" {
  description = "Email address for alerts"
  type        = string
}