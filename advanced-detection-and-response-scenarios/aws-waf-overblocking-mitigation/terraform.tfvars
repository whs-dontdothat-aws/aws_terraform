#--------------------------------------
# 배포 환경 구분 및 기본 설정
#--------------------------------------
environment          = "dev"
aws_region           = "ap-northeast-2"
random_suffix_length = 4

#--------------------------------------
# 주요 리소스명 프리픽스 (모두 랜덤값 붙여서 생성)
#--------------------------------------
name_ec2_malware_test        = "ec2-guardduty-malware-test"
name_ec2_malware_analysis    = "ec2-guardduty-malware-analysis"
name_sg_isolated             = "isolated-sg"
name_subnet_analysis         = "analysis-subnet"
name_route_table_analysis    = "analysis-route-table"
name_nat_gateway_analysis    = "analysis-nat-gateway"
name_s3_guardduty_events     = "s3-sumologic-guardduty-events"
name_s3_logarchive           = "s3-logarchive-bucket"
name_iam_ec2_ssm_role        = "EC2-SSM"
name_iam_sumologic_role      = "iam-sumologic-s3-role"
name_lambda_isolated_sg      = "lambda-isolated-sg"
name_step_functions          = "malware-step-function"
name_api_gateway             = "malware-rest-api"
name_sns_topic               = "sns-malware-protect-alarm"

#--------------------------------------
# Discord Webhook URL (lambda-discord용)
#--------------------------------------
discord_webhook_url = "https://discord.com/api/webhooks/웹후크 작성"

#--------------------------------------
# SNS 이메일 주소 (경보 수신용)
#--------------------------------------
sns_alarm_email = "abc@123.com"