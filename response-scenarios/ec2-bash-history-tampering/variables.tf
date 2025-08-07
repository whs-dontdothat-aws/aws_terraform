# 사용할 AWS 리전을 지정
# 기본값은 서울 리전(ap-northeast-2)
variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "ap-northeast-2"
}

# 생성할 EC2 인스턴스의 타입을 지정
# 기본값은 가장 기본 사양인 t2.micro (프리 티어 포함)
variable "ec2_instance_type" {
  description = "EC2 instance type"
  type        = string
  default     = "t2.micro"
}

# 알림을 받을 디스코드 Webhook URL로 설정
# 해당 URL을 통해 Lambda 함수가 알림을 디스코드 채널로 전송
variable "discord_webhook_url" {
  description = "Discord webhook URL"
  type        = string
}

# 알림을 받을 이메일 주소로 설정
# 보안 이벤트가 발생 시 SNS를 통해 해당 이메일로 알람 전송
variable "sns_email" {
  description = "Email address for SNS subscription"
  type        = string
}