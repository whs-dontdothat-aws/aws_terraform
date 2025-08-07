#--------------------------------------
# lambda-isolated-sg: 감염 인스턴스 격리 Lambda
#--------------------------------------
resource "aws_lambda_function" "lambda_isolated_sg" {
  function_name = "${var.name_lambda_isolated_sg}-${random_id.suffix.hex}"
  filename      = "${path.module}/lambda_zip/lambda-isolated-sg.zip"
  handler       = "lambda-isolated-sg.lambda_handler"
  runtime       = "python3.10"
  timeout       = 60
  environment {
    variables = {
      ISOLATION_SG_ID = aws_security_group.isolated_sg.id
    }
  }
  role = aws_iam_role.lambda_isolated_sg_role.arn
  tags = {
    Name    = "${var.name_lambda_isolated_sg}-${random_id.suffix.hex}"
    Purpose = "Isolate EC2 Instance"
  }
}

#--------------------------------------
# lambda-ebs: 감염 인스턴스 EBS 볼륨 스냅샷 Lambda
#--------------------------------------
resource "aws_lambda_function" "lambda_ebs" {
  function_name = "lambda-ebs-${random_id.suffix.hex}"
  filename      = "${path.module}/lambda_zip/lambda-ebs.zip"
  handler       = "lambda-ebs.lambda_handler"
  runtime       = "python3.10"
  timeout       = 300
  role = aws_iam_role.lambda_ebs_role.arn
  tags = { Name = "lambda-ebs-${random_id.suffix.hex}" }
}

#--------------------------------------
# lambda-ebs-attach: 스냅샷 볼륨을 분석용 EC2에 Attach
#--------------------------------------
resource "aws_lambda_function" "lambda_ebs_attach" {
  function_name = "lambda-ebs-attach-${random_id.suffix.hex}"
  filename      = "${path.module}/lambda_zip/lambda-ebs-attach.zip"
  handler       = "lambda-ebs-attach.lambda_handler"
  runtime       = "python3.10"
  timeout       = 300
  environment {
    variables = {
      TARGET_INSTANCE_ID = aws_instance.malware_analysis.id
    }
  }
  role = aws_iam_role.lambda_ebs_attach_role.arn
  tags = { Name = "lambda-ebs-attach-${random_id.suffix.hex}" }
}

#--------------------------------------
# lambda-ssm: 분석용 EC2에서 SSM 명령 실행
#--------------------------------------
resource "aws_lambda_function" "lambda_ssm" {
  function_name = "lambda-ssm-${random_id.suffix.hex}"
  filename      = "${path.module}/lambda_zip/lambda-ssm.zip"
  handler       = "lambda-ssm.lambda_handler"
  runtime       = "python3.10"
  timeout       = 120
  environment {
    variables = {
      TARGET_INSTANCE_ID = aws_instance.malware_analysis.id
    }
  }
  role = aws_iam_role.lambda_ssm_role.arn
  tags = { Name = "lambda-ssm-${random_id.suffix.hex}" }
}

#--------------------------------------
# lambda-s3: 분석 로그를 S3로 업로드
#--------------------------------------
resource "aws_lambda_function" "lambda_s3" {
  function_name = "lambda-s3-${random_id.suffix.hex}"
  filename      = "${path.module}/lambda_zip/lambda-s3.zip"
  handler       = "lambda-s3.lambda_handler"
  runtime       = "python3.10"
  timeout       = 120
  environment {
    variables = {
      TARGET_INSTANCE_ID = aws_instance.malware_analysis.id
      S3_BUCKET_NAME     = aws_s3_bucket.logarchive.bucket
    }
  }
  role = aws_iam_role.lambda_s3_role.arn
  tags = { Name = "lambda-s3-${random_id.suffix.hex}" }
}

#--------------------------------------
# lambda-discord: 대응 완료 Discord 및 이메일 알림 Lambda
#--------------------------------------
resource "aws_lambda_function" "lambda_discord" {
  function_name = "lambda-discord-${random_id.suffix.hex}"
  filename      = "${path.module}/lambda_zip/lambda-discord.zip"
  handler       = "lambda-discord.lambda_handler"
  runtime       = "python3.10"
  timeout       = 30
  environment {
    variables = {
      WEBHOOK_URL   = var.discord_webhook_url
      SNS_TOPIC_ARN = aws_sns_topic.malware_protect_alarm.arn
    }
  }
  role = aws_iam_role.lambda_discord_role.arn
  tags = { Name = "lambda-discord-${random_id.suffix.hex}" }
}

#--------------------------------------
# lambda-upload-findings-to-s3: GuardDuty Findings S3 업로드 Lambda
#--------------------------------------
resource "aws_lambda_function" "lambda_upload_findings_to_s3" {
  function_name = "lambda-upload-findings-to-s3-${random_id.suffix.hex}"
  filename      = "${path.module}/lambda_zip/lambda-upload-findings-to-s3.zip"
  handler       = "lambda-upload-findings-to-s3.lambda_handler"
  runtime       = "python3.10"
  timeout       = 60
  environment {
    variables = {
      S3_BUCKET = aws_s3_bucket.guardduty_events.bucket
      S3_PREFIX = "guardduty/finding-logs/"
    }
  }
  role = aws_iam_role.lambda_upload_findings_to_s3_role.arn
  tags = { Name = "lambda-upload-findings-to-s3-${random_id.suffix.hex}" }
}
