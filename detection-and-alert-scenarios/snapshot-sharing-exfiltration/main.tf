# Terraform이 리소스를 생성할 AWS 리전 지정
# 아래 코드에서는 us-east-1 리전에 리소스 배포
provider "aws" {
  region = "us-east-1"
}

# EC2 생성하기
# 기본 VPC 정보 가져오기
data "aws_vpc" "default" {
  default = true
}

# 기본 VPC의 서브넷 ID 가져오기
# 여러 서브넷 목록 가져오기
data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}


# Amazon Linux 2 최신 AMI 검색
data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*-x86_64-gp2"]
  }
}

# EC2 인스턴스를 위한 보안 그룹 생성
resource "aws_security_group" "ec2_eg" {
  #name = "ec2-security-group"
  description = "Allow SSH and ICMP"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    description = "Allow ping"
    from_port   = -1
    to_port     = -1
    protocol    = "icmp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "ec2-sh"
  }
}

# EC2 인스턴스 생성
resource "aws_instance" "ebs_snapshot_ec2" {
  ami                    = data.aws_ami.amazon_linux.id
  instance_type          = "t3.micro"
  subnet_id              = data.aws_subnets.default.ids[0]
  vpc_security_group_ids = [aws_security_group.ec2_eg.id]

  associate_public_ip_address = true

  tags = {
    Name = "ebs-snapshot-monitor-ec2"
  }
}


# S3 Bucket for CloudTrail logs
resource "aws_s3_bucket" "cloudtrail_bucket" {
  bucket        = "ebs-snapshot-event-alarm-bucket" # 버킷 이름
  force_destroy = true                              # destroy 할 때 강제로 삭제하게함 (로그 비우고 삭제)
}

# 생성한 S3 버킷에 대한 퍼블릭 액세스 차단
# > 보안 설정을 하는 것임
resource "aws_s3_bucket_public_access_block" "block_public_access" {
  bucket = aws_s3_bucket.cloudtrail_bucket.id

  block_public_acls       = true # 퍼블릭 ACL 지정 차단
  block_public_policy     = true # 퍼블릭한 버킷 정책 차단
  ignore_public_acls      = true # 퍼블릭 ACL 있어도 무시
  restrict_public_buckets = true # 퍼블릭 정책이 있어도 거부
}

# CloudTrail 서비스에 권한 부여
# > 로그를 S3에 정상적으로 쓰기 위해 필요한 권한 정의
resource "aws_s3_bucket_policy" "cloudtrail_bucket_policy" {
  bucket = aws_s3_bucket.cloudtrail_bucket.id

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [ # CloudTrail이 ACL을 읽는 권한 필요
      {
        Sid       = "AWSCloudTrailAclCheck",
        Effect    = "Allow",
        Principal = { Service = "cloudtrail.amazonaws.com" },
        Action    = "s3:GetBucketAcl",
        Resource  = "arn:aws:s3:::${aws_s3_bucket.cloudtrail_bucket.id}"
      },
      { # CloudTrail이 로그 객체를 업로드 할 수 있도록 설정정
        Sid       = "AWSCloudTrailWrite",
        Effect    = "Allow",
        Principal = { Service = "cloudtrail.amazonaws.com" },
        Action    = "s3:PutObject",
        Resource  = "arn:aws:s3:::${aws_s3_bucket.cloudtrail_bucket.id}/AWSLogs/${data.aws_caller_identity.current.account_id}/*",
        Condition = {
          StringEquals = {
            "s3:x-amz-acl" = "bucket-owner-full-control"
          }
        }
      }
    ]
  })
}

# 현재 사용중인 계정 ID 가져옴옴
data "aws_caller_identity" "current" {}

# CloudTrail 설정
resource "aws_cloudtrail" "ebs_snapshot_event_trail" {
  name                          = aws_s3_bucket.cloudtrail_bucket.bucket # Trail 이름름
  s3_bucket_name                = aws_s3_bucket.cloudtrail_bucket.id
  include_global_service_events = true
  is_multi_region_trail         = true
  enable_logging                = true
}

# Lambda 실행 역할
resource "aws_iam_role" "lambda_exec_role" {
  name = "lambda_ebs_snapshot_exec_role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Action = "sts:AssumeRole", # 역할 위임받는 데 필요한 권한 부여여
      Effect = "Allow",
      Principal = {
        Service = "lambda.amazonaws.com"
      }
    }]
  })
}

# Lambda 기본 실행 권한 부여여
resource "aws_iam_role_policy_attachment" "lambda_basic" {
  role       = aws_iam_role.lambda_exec_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# Lambda 함수 정의
resource "aws_lambda_function" "discord_alert" {
  filename         = "lambda_function.zip"
  function_name    = "ebs_snapshot_event_discord"
  role             = aws_iam_role.lambda_exec_role.arn
  handler          = "lambda_function.lambda_handler"
  runtime          = "python3.13"
  source_code_hash = filebase64sha256("lambda_function.zip")
  environment {
    variables = {
      HOOK_URL = var.discord_webhook_url
    }
  }
}

# -> SNS Topic & Email 구독만 설정
resource "aws_sns_topic" "ebs_snapshot_event_topic" {
  name = "ebs-snapshot-event-topic"
}

resource "aws_sns_topic_subscription" "email_subscriber" {
  topic_arn = aws_sns_topic.ebs_snapshot_event_topic.arn
  protocol  = "email"
  endpoint  = var.notification_email
}

# EventBridge 규칙
resource "aws_cloudwatch_event_rule" "ebs_snapshot_event_pattern" {
  name        = "ebs-snapshot-event-pattern"
  description = "Detect EBS Snapshot Event and trigger Lambda & SNS"
  event_pattern = jsonencode({
    "source" : ["aws.ec2"],
    "detail-type" : ["AWS API Call via CloudTrail"],
    "detail" : {
      "eventSource" : ["ec2.amazonaws.com"],
      "eventName" : ["CreateSnapshot", "CreateSnapshots", "DeleteSnapshot", "ModifySnapshotAttribute"]
    }
  })
}

# Lambda와 EventBridge 연결
resource "aws_cloudwatch_event_target" "send_to_lambda" {
  rule      = aws_cloudwatch_event_rule.ebs_snapshot_event_pattern.name
  target_id = "sendToLambda"
  arn       = aws_lambda_function.discord_alert.arn
}

resource "aws_lambda_permission" "allow_eventbridge" {
  statement_id  = "AllowExecutionFromEventBridge"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.discord_alert.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.ebs_snapshot_event_pattern.arn
}

# SNS와 연결
resource "aws_cloudwatch_event_target" "send_to_sns" {
  rule      = aws_cloudwatch_event_rule.ebs_snapshot_event_pattern.name
  target_id = "sendToSNS"
  arn       = aws_sns_topic.ebs_snapshot_event_topic.arn
}

resource "aws_sns_topic_policy" "allow_eventbridge" {
  arn = aws_sns_topic.ebs_snapshot_event_topic.arn
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Sid       = "AllowEventBridgePublish",
        Effect    = "Allow",
        Principal = { Service = "events.amazonaws.com" },
        Action    = "sns:Publish",
        Resource  = aws_sns_topic.ebs_snapshot_event_topic.arn
      }
    ]
  })
}