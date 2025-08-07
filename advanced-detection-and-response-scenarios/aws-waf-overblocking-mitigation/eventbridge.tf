#--------------------------------------
# EventBridge Rule: GuardDuty Findings 감지 시 자동 트리거
#--------------------------------------
resource "aws_cloudwatch_event_rule" "gd_findings_rule" {
  name        = "eventbridge-guardduty-findings-${random_id.suffix.hex}"
  description = "Trigger Lambda on GuardDuty Execution:EC2/MaliciousFile finding"
  event_pattern = jsonencode({
    source = ["aws.guardduty"]
    "detail-type" = ["GuardDuty Finding"]
    detail = {
      type = ["Execution:EC2/MaliciousFile"]
    }
  })
}

#--------------------------------------
# EventBridge Rule Target: Lambda로 연결
#--------------------------------------
resource "aws_cloudwatch_event_target" "gd_findings_lambda" {
  rule      = aws_cloudwatch_event_rule.gd_findings_rule.name
  target_id = "gd-findings-to-s3"
  arn       = aws_lambda_function.lambda_upload_findings_to_s3.arn
}

#--------------------------------------
# Lambda Permission: EventBridge에서 트리거 허용
#--------------------------------------
resource "aws_lambda_permission" "eventbridge_to_lambda" {
  statement_id  = "AllowExecutionFromEventBridge"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.lambda_upload_findings_to_s3.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.gd_findings_rule.arn
}
