#--------------------------------------
# SNS Topic: 자동대응 결과 이메일/디스코드 알람용
#--------------------------------------
resource "aws_sns_topic" "malware_protect_alarm" {
  name = "${var.name_sns_topic}-${random_id.suffix.hex}"

  tags = {
    Name    = "${var.name_sns_topic}-${random_id.suffix.hex}"
    Purpose = "Malware Protection Alarm Notification"
  }
}

#--------------------------------------
# SNS 이메일 구독자(알림 수신 이메일은 tfvars에서 지정)
#--------------------------------------
resource "aws_sns_topic_subscription" "malware_alarm_email" {
  topic_arn = aws_sns_topic.malware_protect_alarm.arn
  protocol  = "email"
  endpoint  = var.sns_alarm_email
}
