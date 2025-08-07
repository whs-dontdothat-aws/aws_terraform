#######################
# 필수 입력 변수
#######################
variable "aws_region" {
  description = "배포할 AWS 리전"
  type        = string
  default     = "ap-northeast-2"
}

variable "my_ip" {
  description = "SSH 허용용 IP/CIDR"
  type        = string
}

variable "alert_email" {
  description = "WAF 차단 알림을 받을 이메일"
  type        = string
}

variable "webhook_url" {
  description = "Discord Webhook URL"
  type        = string
  sensitive   = true
}
