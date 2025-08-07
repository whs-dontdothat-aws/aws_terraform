#--------------------------------------
# 격리용 Security Group (감염 인스턴스 완벽 차단)
#--------------------------------------
resource "aws_security_group" "isolated_sg" {
  name        = "${var.name_sg_isolated}-${random_id.suffix.hex}"
  description = "Security group to fully isolate infected EC2 instances (allow nothing)"
  vpc_id      = aws_vpc.main.id
  # 규칙 없음 (모든 트래픽 차단)
  tags = {
    Name = "${var.name_sg_isolated}-${random_id.suffix.hex}"
  }
}

#--------------------------------------
# 분석용 EC2 Security Group
#--------------------------------------
resource "aws_security_group" "analysis_ec2_sg" {
  name        = "analysis-ec2-sg-${random_id.suffix.hex}"
  description = "SG for forensic analysis EC2 instance, minimum SSH only"
  vpc_id      = aws_vpc.main.id

  ingress {
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
    Name = "analysis-ec2-sg-${random_id.suffix.hex}"
  }
}

#--------------------------------------
# SSM 인터페이스 VPC 엔드포인트용 Security Group (여기만 남기세요)
#--------------------------------------
resource "aws_security_group" "ssm_endpoint_sg" {
  name        = "ssm-endpoint-sg"
  description = "SG for SSM VPC endpoints (443 access for analysis subnet only)"
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [aws_subnet.analysis_subnet.cidr_block]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "ssm-endpoint-sg"
  }
}