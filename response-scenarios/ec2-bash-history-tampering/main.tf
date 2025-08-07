#----------------------------------------------------
# AWS Provider 설정
#----------------------------------------------------
provider "aws" {
  region = var.aws_region   # AWS 리전 설정 (terraform 변수에서 가져옴)
}

#----------------------------------------------------
# 키페어 생성 (EC2 인스턴스 접속용 개인/공개 키 쌍 생성)
#----------------------------------------------------
resource "tls_private_key" "rsa" {
  algorithm = "RSA"       # 키 알고리즘: RSA
  rsa_bits  = 4096        # 키 길이: 4096비트
}

resource "aws_key_pair" "intermediate_1" {
  key_name   = "ec2-bash-history-monitor-key"        # AWS 키페어 이름 - 표와 일치
  public_key = tls_private_key.rsa.public_key_openssh  # 공개키 등록
}

resource "local_file" "private_key" {
  content  = tls_private_key.rsa.private_key_pem     # 개인키 파일 생성 (로컬 저장)
  filename = "ec2-bash-history-monitor-key.pem"      # 파일명 지정
}

#----------------------------------------------------
# 네트워크 구성: VPC, 서브넷, 인터넷 게이트웨이, 라우팅 테이블, 보안그룹
#----------------------------------------------------
resource "aws_vpc" "main" {
  cidr_block = "10.0.0.0/16"    # VPC CIDR 범위
  tags = { Name = "main-vpc" }  # 태그 이름 지정
}

resource "aws_subnet" "main" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.1.0/24"               # 서브넷 CIDR
  availability_zone       = "ap-northeast-2a"           # 가용영역 지정
  map_public_ip_on_launch = true                         # 퍼블릭 IP 자동 할당 활성화
  tags = { Name = "main-subnet" }
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id           # VPC에 연결할 인터넷 게이트웨이
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id    # 인터넷 게이트웨이를 통한 기본 라우팅
  }
}

resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.main.id           # 서브넷에 라우팅 테이블 연결
  route_table_id = aws_route_table.public.id
}

resource "aws_security_group" "default_sg" {
  name        = "default-sg"
  description = "Allow SSH inbound"
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]  # 모든 IP에서 SSH 접속 허용
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]  # 모든 아웃바운드 트래픽 허용
  }
}

resource "aws_security_group" "isolated_sg" {
  name        = "isolated-sg"   # 표 이름과 일치
  description = "Isolated security group with no ingress or egress"
  vpc_id      = aws_vpc.main.id

  ingress = []  # 모든 인바운드 차단 (격리용)
  egress  = []  # 모든 아웃바운드 차단
}

#----------------------------------------------------
# EC2용 IAM 역할과 프로필 (CloudWatch Agent 사용 권한 포함)
#----------------------------------------------------
resource "aws_iam_role" "cloudwatch_agent_role" {
  name = "iam-ec2-cw-agent-role"   # 표에 맞게 변경

  assume_role_policy = jsonencode({
    # EC2가 이 역할을 가정(Assume)할 수 있도록 지정
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "cloudwatch_agent_policy" {
  role       = aws_iam_role.cloudwatch_agent_role.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"  # CloudWatch Agent 정책 연결
}

resource "aws_iam_instance_profile" "cloudwatch_agent_profile" {
  name = "cloudwatch-agent-profile"
  role = aws_iam_role.cloudwatch_agent_role.name   # 위 역할을 인스턴스 프로필에 연결
}

#----------------------------------------------------
# Amazon Linux 2 AMI 데이터 조회 (최신 버전 사용)
#----------------------------------------------------
data "aws_ami" "amazon_linux_2" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*-x86_64-gp2"]
  }
}

#----------------------------------------------------
# EC2 인스턴스 생성 (bash_history 모니터링 목적)
#----------------------------------------------------
resource "aws_instance" "monitored_ec2" {
  ami                    = data.aws_ami.amazon_linux_2.id
  instance_type          = var.ec2_instance_type
  key_name               = aws_key_pair.intermediate_1.key_name
  iam_instance_profile   = aws_iam_instance_profile.cloudwatch_agent_profile.name
  vpc_security_group_ids = [aws_security_group.default_sg.id]
  subnet_id              = aws_subnet.main.id

  # User data 스크립트: CloudWatch Agent 설치 및 bash_history 로그 수집 설정
  user_data = <<-EOF
    #!/bin/bash
    wget https://s3.amazonaws.com/amazoncloudwatch-agent/amazon_linux/amd64/latest/amazon-cloudwatch-agent.rpm
    sudo rpm -Uvh amazon-cloudwatch-agent.rpm
    echo '{
      "logs": {
        "logs_collected": {
          "files": {
            "collect_list": [
              {
                "file_path": "/home/*/.bash_history",
                "log_group_name": "bash_history_logs",
                "log_stream_name": "{instance_id}"
              }
            ]
          }
        }
      }
    }' > /opt/aws/amazon-cloudwatch-agent/bin/config.json
    sudo /opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl -a fetch-config -m ec2 -s -c file:/opt/aws/amazon-cloudwatch-agent/bin/config.json
  EOF

  tags = {
    Name = "ec2-bash-history"     # 표에 맞게 변경
  }
}

#----------------------------------------------------
# CloudWatch 로그 그룹 및 Metric Filter (bash_history 조작 탐지용) 
# 네임스페이스, 메트릭명 모두 표에 맞게 변경
#----------------------------------------------------
resource "aws_cloudwatch_log_group" "bash_history_logs" {
  name = "bash_history_logs"
}

resource "aws_cloudwatch_log_metric_filter" "bash_history_tamper1" {
  name           = "bash-history-tampering"                # 표와 매칭
  pattern        = "history -c"                            # bash_history 초기화 명령 패턴
  log_group_name = aws_cloudwatch_log_group.bash_history_logs.name

  metric_transformation {
    name      = "bash-history-tampering"                  # 표와 일치하는 메트릭 이름
    namespace = "ec2-security-monitor"                     # 표와 매칭된 네임스페이스
    value     = "1"
  }
}

# 추가 tamper2, tamper3 패턴을 동일 metric에 누적시키기 위해 alias로 추가 생성 가능 
# (필요 시만 적용, 아니면 하나만 사용해도 무방)

#----------------------------------------------------
# CloudWatch Metric Alarm (bash_history tampering 감지 시 SNS 알람 발생)
# 표와 이름을 맞춤
#----------------------------------------------------
resource "aws_cloudwatch_metric_alarm" "bash_history_alarm" {
  alarm_name          = "alarms-ec2-bash-history"          # 표와 이름 일치
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 1
  metric_name         = "bash-history-tampering"           # 표와 메트릭명 일치
  namespace           = "ec2-security-monitor"             # 표와 네임스페이스 일치
  period              = 60
  statistic           = "Sum"
  threshold           = 1                      # 1 이상이면 알람 발생
  alarm_description   = "Detects tampering with bash_history"
  alarm_actions       = [aws_sns_topic.alarm_notifications.arn]  # SNS로 알람 전송
}

#----------------------------------------------------
# SNS Topic 및 구독 설정 (이메일 및 Lambda)
#----------------------------------------------------
resource "aws_sns_topic" "alarm_notifications" {
  name = "sns-bash-alarm"  # 표와 일치하는 SNS 토픽 이름
}

resource "aws_sns_topic_subscription" "email_subscription" {
  topic_arn = aws_sns_topic.alarm_notifications.arn
  protocol  = "email"
  endpoint  = var.sns_email     # 이메일 주소 (변수)
}

# Lambda 권한: SNS가 Lambda 함수를 호출할 수 있도록 허용
resource "aws_lambda_permission" "allow_sns" {
  statement_id  = "AllowExecutionFromSNS"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.bash_history_responder.function_name
  principal     = "sns.amazonaws.com"
  source_arn    = aws_sns_topic.alarm_notifications.arn
}

resource "aws_sns_topic_subscription" "lambda_subscription" {
  topic_arn = aws_sns_topic.alarm_notifications.arn
  protocol  = "lambda"
  endpoint  = aws_lambda_function.bash_history_responder.arn

  # 의존성 명시: Lambda 및 권한이 생성된 후 실행되도록 보장
  depends_on = [
    aws_lambda_function.bash_history_responder,
    aws_lambda_permission.allow_sns
  ]
}

#----------------------------------------------------
# Lambda 실행 역할 및 권한 설정 (표에 맞는 역할, 권한 이름과 연결)
#----------------------------------------------------
resource "aws_iam_role" "lambda_exec" {
  name = "lambda-exec-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_basic" {
  role       = aws_iam_role.lambda_exec.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"  # Lambda 기본 실행 권한
}

resource "aws_iam_role_policy" "lambda_ec2_sg" {
  name = "lambda-ec2-sg-policy"
  role = aws_iam_role.lambda_exec.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "ec2:DescribeInstances",        # EC2 인스턴스 조회 권한
        "ec2:ModifyInstanceAttribute",  # 인스턴스 속성 수정 권한 (보안 그룹 변경 등)
        "ec2:CreateSnapshot"            # EBS 스냅샷 생성 권한
      ]
      Resource = "*"
    }]
  })
}

#----------------------------------------------------
# Lambda 함수 정의: bash_history 조작 탐지 알람 수신 시 Discord 알림 전송 및 EC2 보안 그룹 변경 등 처리
# 표에 맞게 함수 이름 변경함
#----------------------------------------------------
resource "aws_lambda_function" "bash_history_responder" {
  filename      = "lambda.zip"    # 패키지된 Lambda 코드 파일
  function_name = "sns-bash-history-alarm"  # 표에 맞게 변경
  role          = aws_iam_role.lambda_exec.arn
  handler       = "lambda_function.lambda_handler"  # 진입점 핸들러
  runtime       = "python3.8"

  environment {   # Lambda 실행 시점 환경 변수
    variables = {
      DISCORD_WEBHOOK_URL = var.discord_webhook_url  # 디스코드 웹훅 URL
      EC2_ID              = aws_instance.monitored_ec2.id
      ISOLATED_SG_ID      = aws_security_group.isolated_sg.id
    }
  }
}
