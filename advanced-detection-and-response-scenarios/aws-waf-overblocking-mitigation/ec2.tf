#--------------------------------------
# TLS 키쌍 자동 생성 (malware_test)
#--------------------------------------
resource "tls_private_key" "malware_test" {
  algorithm = "RSA"
  rsa_bits  = 2048
}

resource "local_file" "malware_test_private_key" {
  filename         = "${path.module}/keys/guardduty-malware-${random_id.suffix.hex}.pem"
  content          = tls_private_key.malware_test.private_key_pem
  file_permission  = "0600"
}

resource "local_file" "malware_test_public_key" {
  filename = "${path.module}/keys/guardduty-malware-${random_id.suffix.hex}.pub"
  content  = tls_private_key.malware_test.public_key_openssh
}

resource "aws_key_pair" "malware_test" {
  key_name   = "guardduty-malware-${random_id.suffix.hex}"
  public_key = tls_private_key.malware_test.public_key_openssh
}

#--------------------------------------
# TLS 키쌍 자동 생성 (malware_analysis)
#--------------------------------------
resource "tls_private_key" "malware_analysis" {
  algorithm = "RSA"
  rsa_bits  = 2048
}

resource "local_file" "malware_analysis_private_key" {
  filename         = "${path.module}/keys/guardduty-malware-analysis-${random_id.suffix.hex}.pem"
  content          = tls_private_key.malware_analysis.private_key_pem
  file_permission  = "0600"
}

resource "local_file" "malware_analysis_public_key" {
  filename = "${path.module}/keys/guardduty-malware-analysis-${random_id.suffix.hex}.pub"
  content  = tls_private_key.malware_analysis.public_key_openssh
}

resource "aws_key_pair" "malware_analysis" {
  key_name   = "guardduty-malware-analysis-${random_id.suffix.hex}"
  public_key = tls_private_key.malware_analysis.public_key_openssh
}

#--------------------------------------
# 감염 테스트용 EC2 인스턴스
#--------------------------------------
resource "aws_instance" "malware_test" {
  ami                         = "ami-0fc8aeaa301af7663"   # 서울 리전 Amazon Linux 2023 (예시)
  instance_type               = "t2.micro"
  subnet_id                   = aws_subnet.public_subnet.id
  vpc_security_group_ids      = [aws_security_group.analysis_ec2_sg.id]
  key_name                    = aws_key_pair.malware_test.key_name
  iam_instance_profile        = aws_iam_instance_profile.ec2_ssm_profile.name
  associate_public_ip_address = true

  tags = {
    Name = "${var.name_ec2_malware_test}-${random_id.suffix.hex}"
    Role = "malware-test"
  }
  user_data = <<EOF
#!/bin/bash
yum install -y curl
curl -o /home/ec2-user/eicar.com https://secure.eicar.org/eicar.com.txt
EOF
}


#--------------------------------------
# 분석용 EC2 인스턴스
#--------------------------------------
resource "aws_instance" "malware_analysis" {
  ami                         = "ami-0fc8aeaa301af7663"   # 서울 리전 Amazon Linux 2023 (예시)
  instance_type               = "t2.micro"
  subnet_id                   = aws_subnet.analysis_subnet.id
  vpc_security_group_ids      = [aws_security_group.analysis_ec2_sg.id]
  key_name                    = aws_key_pair.malware_analysis.key_name
  iam_instance_profile        = aws_iam_instance_profile.ec2_ssm_profile.name
  associate_public_ip_address = false

  tags = {
    Name = "${var.name_ec2_malware_analysis}-${random_id.suffix.hex}"
    Role = "malware-analysis"
  }

  # 인스턴스 최초 부팅 시 실행되는 스크립트 (user_data)
  user_data = <<EOF
#!/bin/bash
# OS 업데이트 및 SSM Agent 설치/활성화 스크립트

# yum 패키지 업데이트
yum update -y

# amazon-ssm-agent 설치 (Amazon Linux 2023은 기본 내장, 그래도 재설치)
yum install -y amazon-ssm-agent

# SSM Agent 데몬을 부팅 시 자동 시작하도록 활성화
systemctl enable amazon-ssm-agent

# SSM Agent 즉시 시작
systemctl start amazon-ssm-agent
EOF
}


#--------------------------------------
# EC2용 IAM 인스턴스 프로파일 (SSM 및 S3 접근 권한 포함)
#--------------------------------------
resource "aws_iam_instance_profile" "ec2_ssm_profile" {
  name = "${var.name_iam_ec2_ssm_role}-${random_id.suffix.hex}"
  role = aws_iam_role.ec2_ssm_role.name
}
