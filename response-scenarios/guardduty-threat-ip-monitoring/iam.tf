#--------------------------------------
# Lambda: IP 목록 업데이트 권한
#--------------------------------------

# Lambda 함수가 실행되기 위해 필요한 IAM 역할 생성
# 이 역할은 S3에 파일을 쓰고, 로그를 기록할 수 있는 권한이 필요
resource "aws_iam_role" "lambda_update_ip_list_role" {
  name = "lambda-update-ip-list-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Effect = "Allow",
      Principal = { Service = "lambda.amazonaws.com" }, # Lambda 서비스가 이 역할을 사용할 수 있도록 허용
      Action   = "sts:AssumeRole"
    }]
  })
}

#--------------------------------------
# Lambda가 로그를 CloudWatch에 기록하고, S3에 악성 IP 파일을 업로드할 수 있도록 허용하는 정책 부여
#--------------------------------------
resource "aws_iam_role_policy" "lambda_update_ip_list_policy" {
  name = "lambda-update-ip-list-policy"
  role = aws_iam_role.lambda_update_ip_list_role.id
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Action = ["logs:*"],       # CloudWatch Logs 관련 모든 작업 허용
        Resource = "*"
      },
      {
        Effect = "Allow",
        Action = ["s3:PutObject"], # S3에 악성 IP 파일을 업로드하기 위한 권한
        Resource = "${aws_s3_bucket.ip_list_bucket.arn}/*"
      }
    ]
  })
}

#--------------------------------------
# Lambda: Discord + EC2 대응 권한
#--------------------------------------

#--------------------------------------
# 디스코드 알림과 EC2 스냅샷 생성/정지를 위한 Lambda에 필요한 역할 정의
#--------------------------------------
resource "aws_iam_role" "discord_and_ec2_alarm_role" {
  name = "discord-and-ec2-alarm-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Effect = "Allow",
      Principal = { Service = "lambda.amazonaws.com" }, # Lambda 서비스가 이 역할을 사용할 수 있도록 허용
      Action   = "sts:AssumeRole"
    }]
  })
}

#--------------------------------------
# 해당 역할에 필요한 EC2 및 로그 관련 권한 부여
#--------------------------------------
resource "aws_iam_role_policy" "discord_and_ec2_alarm_policy" {
  name = "discord-and-ec2-alarm-policy"
  role = aws_iam_role.discord_and_ec2_alarm_role.id
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Action = ["logs:*"],       # CloudWatch Logs 기록을 위한 권한
        Resource = "*"
      },
      {
        Effect = "Allow",
        Action = [
          "ec2:DescribeInstances",  # EC2 인스턴스 정보 확인
          "ec2:StopInstances",      # EC2 인스턴스 중지
          "ec2:DescribeVolumes",    # EBS 볼륨 정보 확인
          "ec2:CreateSnapshot"      # 스냅샷 생성
        ],
        Resource = "*"
      }
    ]
  })
}

#--------------------------------------
# EventBridge → SNS 호출을 위한 IAM 역할
#--------------------------------------

# EventBridge가 SNS 주제를 호출할 수 있도록 허용하는 역할 생성
resource "aws_iam_role" "eventbridge_invoke_sns_role" {
  name = "eventbridge-invoke-sns-role"

  # 이 역할을 EventBridge 서비스가 Assume(사용)할 수 있도록 허용
  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Effect = "Allow",
      Principal = {
        Service = "events.amazonaws.com"  # EventBridge 서비스에게 역할 사용 허용
      },
      Action = "sts:AssumeRole"
    }]
  })
}

#--------------------------------------
# 위 역할에 SNS publish 권한을 부여하는 정책 정의
#--------------------------------------
resource "aws_iam_role_policy" "eventbridge_invoke_sns_policy" {
  name = "eventbridge-invoke-sns-policy"
  role = aws_iam_role.eventbridge_invoke_sns_role.id

  # 정책 내용: SNS 주제에 Publish(메시지 발송) 권한 부여
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Effect = "Allow",
      Action = [
        "sns:Publish"  # SNS에 메시지 전송 권한
      ],
      Resource = aws_sns_topic.threat_ip_alarm.arn  # 대상 SNS 주제 ARN
    }]
  })
}
