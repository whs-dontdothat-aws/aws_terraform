#--------------------------------------
# VPC 생성
#--------------------------------------
resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "guardduty-malware-vpc"
  }
}

#--------------------------------------
# 퍼블릭 서브넷 (NAT Gateway 용)
#--------------------------------------
resource "aws_subnet" "public_subnet" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.0.0/24"
  map_public_ip_on_launch = true
  availability_zone       = "ap-northeast-2a"

  tags = {
    Name = "public-subnet"
  }
}

#--------------------------------------
# 분석용 프라이빗 서브넷
#--------------------------------------
resource "aws_subnet" "analysis_subnet" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.1.0/24"
  availability_zone = "ap-northeast-2a"

  tags = {
    Name = var.name_subnet_analysis
  }
}

#--------------------------------------
# 인터넷 게이트웨이 (퍼블릭 서브넷용)
#--------------------------------------
resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "guardduty-malware-igw"
  }
}

#--------------------------------------
# NAT Gateway용 탄력적 IP 할당
#--------------------------------------
resource "aws_eip" "nat_eip" {
  vpc = true

  tags = {
    Name = "nat-eip"
  }
}

#--------------------------------------
# NAT Gateway (분석용 서브넷 아웃바운드용)
#--------------------------------------
resource "aws_nat_gateway" "analysis_nat_gateway" {
  allocation_id = aws_eip.nat_eip.id
  subnet_id     = aws_subnet.public_subnet.id

  tags = {
    Name = var.name_nat_gateway_analysis
  }
}

#--------------------------------------
# 라우팅 테이블 (분석용 서브넷 전용)
#--------------------------------------
resource "aws_route_table" "analysis_route_table" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.analysis_nat_gateway.id
  }

  tags = {
    Name = var.name_route_table_analysis
  }
}

#--------------------------------------
# 라우팅 테이블과 서브넷 연결 (분석용)
#--------------------------------------
resource "aws_route_table_association" "analysis_subnet_assoc" {
  subnet_id      = aws_subnet.analysis_subnet.id
  route_table_id = aws_route_table.analysis_route_table.id
}

#--------------------------------------
# VPC 엔드포인트들 - 보안 그룹만 참조 (선언 X)
#--------------------------------------
resource "aws_vpc_endpoint" "ssm" {
  vpc_id             = aws_vpc.main.id
  service_name       = "com.amazonaws.${var.aws_region}.ssm"
  vpc_endpoint_type  = "Interface" 
  subnet_ids         = [aws_subnet.analysis_subnet.id]
  security_group_ids = [aws_security_group.ssm_endpoint_sg.id]
  private_dns_enabled = true

  tags = {
    Name = "com.amazonaws.${var.aws_region}.ssm"
  }
}

resource "aws_vpc_endpoint" "ec2messages" {
  vpc_id             = aws_vpc.main.id
  service_name       = "com.amazonaws.${var.aws_region}.ec2messages"
  vpc_endpoint_type  = "Interface" 
  subnet_ids         = [aws_subnet.analysis_subnet.id]
  security_group_ids = [aws_security_group.ssm_endpoint_sg.id]
  private_dns_enabled = true

  tags = {
    Name = "com.amazonaws.${var.aws_region}.ec2messages"
  }
}

resource "aws_vpc_endpoint" "ssmmessages" {
  vpc_id             = aws_vpc.main.id
  service_name       = "com.amazonaws.${var.aws_region}.ssmmessages"
  vpc_endpoint_type  = "Interface" 
  subnet_ids         = [aws_subnet.analysis_subnet.id]
  security_group_ids = [aws_security_group.ssm_endpoint_sg.id]
  private_dns_enabled = true

  tags = {
    Name = "com.amazonaws.${var.aws_region}.ssmmessages"
  }
}

#---------------------------------------------------------
# 퍼블릭 서브넷용 라우팅 테이블 및 IGW 경로 추가
#---------------------------------------------------------
resource "aws_route_table" "public_route_table" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }
  tags = {
    Name = "public-route-table"
  }
}

# 퍼블릭 서브넷과 라우팅 테이블 연결
resource "aws_route_table_association" "public_subnet_assoc" {
  subnet_id      = aws_subnet.public_subnet.id
  route_table_id = aws_route_table.public_route_table.id
}

