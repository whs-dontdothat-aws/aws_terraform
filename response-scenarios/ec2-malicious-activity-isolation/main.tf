provider "aws" {
  region = var.aws_region  # 사용할 AWS 리전 (서울: ap-northeast-2)
}

# 키 페어 생성 (SSH 접속용)
resource "tls_private_key" "rsa" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "aws_key_pair" "intermediate_1" {
  key_name   = "intermediate1"
  public_key = tls_private_key.rsa.public_key_openssh
}

resource "local_file" "private_key" {
  content  = tls_private_key.rsa.private_key_pem
  filename = "intermediate1.pem"  # 개인키를 파일로 저장
}

# GuardDuty 활성화
resource "aws_guardduty_detector" "main" {
  enable = true
}

# GuardDuty Findings 감지를 위한 CloudWatch Event Rule 설정
resource "aws_cloudwatch_event_rule" "guardduty_findings" {
  name = "guardduty-findings-rule"
  description = "Trigger on GuardDuty high severity findings"
  event_pattern = jsonencode({
    source = ["aws.guardduty"],
    "detail-type" = ["GuardDuty Finding"],
    detail = {
      severity = [{
        "numeric": [">=", 7.0]
      }]
    }
  })
}

# CloudWatch Event Target -> SNS 주제 연결
resource "aws_cloudwatch_event_target" "sns_target" {
  rule = aws_cloudwatch_event_rule.guardduty_findings.name
  target_id = "SendToSNS"
  arn = aws_sns_topic.alarm_notifications.arn
}

# EventBridge가 SNS 주제를 Publish 할 수 있도록 권한 부여
resource "aws_sns_topic_policy" "allow_eventbridge" {
  arn = aws_sns_topic.alarm_notifications.arn

  policy = jsonencode({
    Version: "2012-10-17",
    Statement: [{
      Sid: "AllowEventBridgePublish",
      Effect: "Allow",
      Principal: {
        Service: "events.amazonaws.com"
      },
      Action: "sns:Publish",
      Resource: aws_sns_topic.alarm_notifications.arn
    }]
  })
}

# VPC, 서브넷, IGW, 보안 그룹 등 네트워크 구성
resource "aws_vpc" "main" {
  cidr_block = "10.0.0.0/16"
  tags = { Name = "main-vpc" }
}

resource "aws_subnet" "main" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = "ap-northeast-2a"  # 가용 영역 지정
  map_public_ip_on_launch = true  # 퍼블릭 IP 자동 할당
  tags = { Name = "main-subnet" }
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id
  route {
    cidr_block = "0.0.0.0/0"  # 모든 트래픽 허용
    gateway_id = aws_internet_gateway.igw.id
  }
}

resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.main.id
  route_table_id = aws_route_table.public.id
}

# EC2 SSH 허용 SG
resource "aws_security_group" "default_sg" {
  name        = "default-sg"
  description = "Allow SSH inbound"
  vpc_id      = aws_vpc.main.id
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]  # 모든 IP에서 SSH 허용
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# 완전 차단용 격리 SG (보안 그룹)
resource "aws_security_group" "isolated_sg" {
  name        = "isolated-sg"
  description = "No access security group for isolation"
  vpc_id      = aws_vpc.main.id
  ingress = []  # 인바운드 없음
  egress  = []  # 아웃바운드 없음
}

# CloudWatch Agent가 EC2에서 실행될 수 있도록 하는 IAM Role
resource "aws_iam_role" "cloudwatch_agent_role" {
  name = "iam-ec2-cw-agent-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Action = "sts:AssumeRole",
      Effect = "Allow",
      Principal = { Service = "ec2.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "cloudwatch_agent_policy" {
  role       = aws_iam_role.cloudwatch_agent_role.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"  # CloudWatch Agent 실행 권한
}

resource "aws_iam_instance_profile" "cloudwatch_agent_profile" {
  name = "cloudwatch-agent-profile"
  role = aws_iam_role.cloudwatch_agent_role.name
}

# 최신 Amazon Linux 2 AMI 조회 (자동)
data "aws_ami" "amazon_linux_2" {
  most_recent = true
  owners      = ["amazon"]
  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*-x86_64-gp2"]
  }
}

# EC2 인스턴스 생성 + CloudWatch Agent 설정
resource "aws_instance" "monitored_ec2" {
  ami                    = data.aws_ami.amazon_linux_2.id
  instance_type          = var.ec2_instance_type
  key_name               = aws_key_pair.intermediate_1.key_name
  iam_instance_profile   = aws_iam_instance_profile.cloudwatch_agent_profile.name
  vpc_security_group_ids = [aws_security_group.default_sg.id]
  subnet_id              = aws_subnet.main.id
  tags = { Name = "ec2-guardduty-monitor" }
}

#---여기까지 워크북 기준 3,4,5번---#
# SNS 주제 생성 (알림 발송용)
resource "aws_sns_topic" "alarm_notifications" {
  name = "sns-guardduty-topic"
}

# 이메일 구독자 추가 (SNS 알림용)
resource "aws_sns_topic_subscription" "email_subscription" {
  topic_arn = aws_sns_topic.alarm_notifications.arn
  protocol  = "email"
  endpoint  = var.sns_email
}

# Lambda 구독 추가 (디스코드 알림용)
resource "aws_sns_topic_subscription" "lambda_subscription" {
  topic_arn = aws_sns_topic.alarm_notifications.arn
  protocol  = "lambda"
  endpoint  = aws_lambda_function.guardduty_function.arn
}

# Lambda 함수가 SNS로부터 호출될 수 있도록 권한 부여
resource "aws_lambda_permission" "allow_sns" {
  statement_id  = "AllowExecutionFromSNS"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.guardduty_function.function_name
  principal     = "sns.amazonaws.com"
  source_arn    = aws_sns_topic.alarm_notifications.arn
}

# Lambda 함수용 IAM 역할 생성
resource "aws_iam_role" "lambda_exec" {
  name = "lambda-exec-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Action = "sts:AssumeRole",
      Effect = "Allow",
      Principal = { Service = "lambda.amazonaws.com" }
    }]
  })
}

# Lambda 실행을 위한 기본 정책 연결
resource "aws_iam_role_policy_attachment" "lambda_basic" {
  role       = aws_iam_role.lambda_exec.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# Lambda가 EC2를 격리용 보안 그룹으로 격리시키기 위한 IAM Role 설정
resource "aws_iam_role_policy" "lambda_ec2_sg" {
  name = "lambda-ec2-sg-policy"
  role = aws_iam_role.lambda_exec.id
  policy = jsonencode({
    "Version": "2012-10-17",
    "Statement": [
      {
        "Sid": "GuardDutyReadAccess",
        "Effect": "Allow",
        "Action": [
          "guardduty:GetFindings",
          "guardduty:ListDetectors",
          "guardduty:ListFindings"
        ],
        "Resource": "*"
      },
      {
        "Sid": "EC2DescribeAndModify",
        "Effect": "Allow",
        "Action": [
          "ec2:DescribeInstances",
          "ec2:DescribeNetworkInterfaces",
          "ec2:ModifyNetworkInterfaceAttribute",
          "ec2:CreateTags"
        ],
        "Resource": "*"
      },
      {
        "Sid": "IAMListUsersForLogging",
        "Effect": "Allow",
        "Action": [
          "iam:ListUsers"
        ],
        "Resource": "*"
      },
      {
        "Sid": "SNSPublishAccessIfUsed",
        "Effect": "Allow",
        "Action": [
          "sns:Publish"
        ],
        "Resource": "*"
      }
    ]
  })
}

# Lambda 함수 정의 (디스코드에 알림 전송, EC2 조작)
resource "aws_lambda_function" "guardduty_function" {
  filename      = "lambda_function.zip"
  function_name = "sns-guardduty-alarm"
  role          = aws_iam_role.lambda_exec.arn
  handler       = "lambda_function.lambda_handler"
  runtime       = "python3.8"

  environment {
    variables = {
      DISCORD_WEBHOOK_URL = var.discord_webhook_url
      # EC2_ID              = aws_instance.monitored_ec2.id
      ISOLATED_SG_ID      = aws_security_group.isolated_sg.id
    }
  }
}