# 해당 파일에서는 변수를 여기다가 모두 선언
# terraform 실행 시 terraform.tfvars에 선언된 값을 바탕으로 값이 들어감

variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "ap-northeast-2" # 또는 원하는 리전
}

variable "account_id" {}
variable "cloudtrail_name" { default = "ct-logaudit" }
variable "s3_bucket_name" { default = "s3-cloudtrail-logbucket" }
variable "lambda_role_name" { default = "lambda-athena-secmonitor" }
variable "lambda_function_name" { default = "lambda-athena-secmonitor" }
variable "sns_topic_name" { default = "sns-athena-alarm" }
variable "eventbridge_rule_name" { default = "eventbridge-athena-schedule" }
variable "athena_db" { default = "athena_cloudtrail_db" }
variable "athena_table" { default = "cloudtrail_table" }
variable "glue_role_name" { default = "AWSGlueServiceRole-ct" }

variable "discord_webhook_url" {
  description = "Discord Webhook URL"
  type        = string
}

variable "sns_email" {
  description = "Email address for SNS subscription"
  type        = string
}

