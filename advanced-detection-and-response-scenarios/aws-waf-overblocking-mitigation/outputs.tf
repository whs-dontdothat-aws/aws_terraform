#--------------------------------------
# 주요 리소스 출력: EC2 인스턴스
#--------------------------------------
output "malware_test_instance_id" {
  description = "감염 테스트용 EC2 인스턴스 ID"
  value       = aws_instance.malware_test.id
}

output "malware_test_instance_name" {
  description = "감염 테스트용 EC2 인스턴스 이름"
  value       = aws_instance.malware_test.tags.Name
}

output "malware_analysis_instance_id" {
  description = "분석용 EC2 인스턴스 ID"
  value       = aws_instance.malware_analysis.id
}

output "malware_analysis_instance_name" {
  description = "분석용 EC2 인스턴스 이름"
  value       = aws_instance.malware_analysis.tags.Name
}

#--------------------------------------
# S3 버킷 출력
#--------------------------------------
output "s3_guardduty_events_bucket" {
  description = "GuardDuty Findings 저장용 S3 버킷 이름"
  value       = aws_s3_bucket.guardduty_events.bucket
}

output "s3_logarchive_bucket" {
  description = "로그 아카이브용 S3 버킷 이름"
  value       = aws_s3_bucket.logarchive.bucket
}

#--------------------------------------
# Security Group 출력
#--------------------------------------
output "isolated_sg_id" {
  description = "격리용 보안 그룹 ID"
  value       = aws_security_group.isolated_sg.id
}

#--------------------------------------
# Lambda 함수 ARN 출력
#--------------------------------------
output "lambda_isolated_sg_arn" {
  description = "감염 인스턴스 격리 Lambda 함수 ARN"
  value       = aws_lambda_function.lambda_isolated_sg.arn
}

output "lambda_ebs_arn" {
  description = "EBS 스냅샷 Lambda 함수 ARN"
  value       = aws_lambda_function.lambda_ebs.arn
}

output "lambda_ebs_attach_arn" {
  description = "EBS 볼륨 Attach Lambda 함수 ARN"
  value       = aws_lambda_function.lambda_ebs_attach.arn
}

output "lambda_ssm_arn" {
  description = "SSM 명령 실행 Lambda 함수 ARN"
  value       = aws_lambda_function.lambda_ssm.arn
}

output "lambda_s3_arn" {
  description = "S3 업로드 Lambda 함수 ARN"
  value       = aws_lambda_function.lambda_s3.arn
}

output "lambda_discord_arn" {
  description = "Discord 알림 Lambda 함수 ARN"
  value       = aws_lambda_function.lambda_discord.arn
}

output "lambda_upload_findings_to_s3_arn" {
  description = "GuardDuty Findings S3 업로드 Lambda 함수 ARN"
  value       = aws_lambda_function.lambda_upload_findings_to_s3.arn
}

#--------------------------------------
# Step Functions 출력
#--------------------------------------
output "step_functions_arn" {
  description = "Malware 자동대응 Step Functions ARN"
  value       = aws_sfn_state_machine.malware_step.arn
}

output "step_functions_name" {
  description = "Step Functions 이름"
  value       = aws_sfn_state_machine.malware_step.name
}

#--------------------------------------
# API Gateway 출력
#--------------------------------------
output "api_gateway_invoke_url" {
  description = "API Gateway invoke URL (Webhook 주소)"
  value       = aws_api_gateway_deployment.malware_api.invoke_url
}

#--------------------------------------
# SNS Topic 출력
#--------------------------------------
output "sns_topic_arn" {
  description = "Malware 알람 SNS Topic ARN"
  value       = aws_sns_topic.malware_protect_alarm.arn
}

#--------------------------------------
# EventBridge Rule 출력
#--------------------------------------
output "eventbridge_rule_name" {
  description = "GuardDuty Findings EventBridge Rule 이름"
  value       = aws_cloudwatch_event_rule.gd_findings_rule.name
}

#--------------------------------------
# VPC 관련 출력 (예시)
#--------------------------------------
output "analysis_subnet_id" {
  description = "분석용 서브넷 ID"
  value       = aws_subnet.analysis_subnet.id
}

output "analysis_route_table_id" {
  description = "분석용 라우팅 테이블 ID"
  value       = aws_route_table.analysis_route_table.id
}

output "analysis_nat_gateway_id" {
  description = "분석용 NAT Gateway ID"
  value       = aws_nat_gateway.analysis_nat_gateway.id
}

#--------------------------------------
# VPC Endpoint 출력 (SSM 관련)
#--------------------------------------
output "ssm_vpc_endpoint_id" {
  description = "SSM VPC Endpoint ID"
  value       = aws_vpc_endpoint.ssm.id
}

output "ec2messages_vpc_endpoint_id" {
  description = "EC2 Messages VPC Endpoint ID"
  value       = aws_vpc_endpoint.ec2messages.id
}

output "ssmmessages_vpc_endpoint_id" {
  description = "SSM Messages VPC Endpoint ID"
  value       = aws_vpc_endpoint.ssmmessages.id
}
