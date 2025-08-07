#--------------------------------------
# 환경 구분 변수 (dev, prod 등)
# 배포 환경별 자원명 구분 및 설정용
#--------------------------------------
variable "environment" {
  type        = string
  description = "Deployment environment for differentiation. Example: dev, prod"
  default     = "dev"
}

#--------------------------------------
# AWS 리전 변수
#--------------------------------------
variable "aws_region" {
  type        = string
  description = "AWS Region to deploy resources"
  default     = "ap-northeast-2"  # 서울 리전 기본 설정
}

#--------------------------------------
# 랜덤 접미사 바이트 길이 변수
# 네이밍 충돌 방지를 위한 랜덤 접미사 길이 (4바이트 = 8자리 16진수)
#--------------------------------------
variable "random_suffix_length" {
  type        = number
  description = "Byte length of random suffix for resource names"
  default     = 4
}

#--------------------------------------
# 주요 리소스 이름 기본값 변수들
# 기존 시나리오에 맞는 대표 이름을 변수로 선언 (랜덤 suffix는 별도 조합)
#--------------------------------------

variable "name_ec2_malware_test" {
  type        = string
  description = "Name prefix for the infected test EC2 instance"
  default     = "ec2-guardduty-malware-test"
}

variable "name_ec2_malware_analysis" {
  type        = string
  description = "Name prefix for the forensic analysis EC2 instance"
  default     = "ec2-guardduty-malware-analysis"
}

variable "name_sg_isolated" {
  type        = string
  description = "Name for the isolation security group"
  default     = "isolated-sg"
}

variable "name_subnet_analysis" {
  type        = string
  description = "Name for the analysis subnet"
  default     = "analysis-subnet"
}

variable "name_route_table_analysis" {
  type        = string
  description = "Name for the analysis route table"
  default     = "analysis-route-table"
}

variable "name_nat_gateway_analysis" {
  type        = string
  description = "Name for the analysis NAT gateway"
  default     = "analysis-nat-gateway"
}

variable "name_s3_guardduty_events" {
  type        = string
  description = "S3 bucket name for GuardDuty event logs (must be globally unique; random suffix appended)"
  default     = "s3-sumologic-guardduty-events"
}

variable "name_s3_logarchive" {
  type        = string
  description = "S3 bucket name for log archive"
  default     = "s3-logarchive-bucket"
}

variable "name_iam_ec2_ssm_role" {
  type        = string
  description = "IAM Role name for EC2 SSM access"
  default     = "EC2-SSM"
}
/*
variable "name_iam_sumologic_role" {
  type        = string
  description = "IAM Role name for Sumo Logic S3 access"
  default     = "iam-sumologic-s3-role"
}
*/
variable "name_lambda_isolated_sg" {
  type        = string
  description = "Lambda function name to isolate infected instance security group"
  default     = "lambda-isolated-sg"
}

variable "name_step_functions" {
  type        = string
  description = "Step Function State Machine name"
  default     = "malware-step-function"
}

variable "name_api_gateway" {
  type        = string
  description = "API Gateway name for malware webhook"
  default     = "malware-rest-api"
}

variable "name_sns_topic" {
  type        = string
  description = "SNS Topic name for malware protection alarm"
  default     = "sns-malware-protect-alarm"
}

#--------------------------------------
# Discord Webhook URL (Lambda-discord 환경변수용)
#--------------------------------------
variable "discord_webhook_url" {
  type        = string
  description = "Discord webhook URL for malware notifications"
}

#--------------------------------------
# SNS 이메일 주소 (SNS 구독자)
#--------------------------------------
variable "sns_alarm_email" {
  type        = string
  description = "Email address to receive SNS malware alarms"
}
