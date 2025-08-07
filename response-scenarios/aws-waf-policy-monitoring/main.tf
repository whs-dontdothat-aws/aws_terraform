###############################################################################
# 0. Terraform & Provider
###############################################################################
terraform {
  required_version = ">= 1.6"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

###############################################################################
# 1. 네트워크 (VPC / Subnet / IGW / Route Table)
###############################################################################
resource "aws_vpc" "main" {
  cidr_block = "10.0.0.0/16"
  tags       = { Name = "waf-vpc" }
}

resource "aws_subnet" "a" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = "${var.aws_region}a"
  map_public_ip_on_launch = true
  tags                    = { Name = "waf-subnet-a" }
}

resource "aws_subnet" "c" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.2.0/24"
  availability_zone       = "${var.aws_region}c"
  map_public_ip_on_launch = true
  tags                    = { Name = "waf-subnet-c" }
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id
  tags   = { Name = "waf-igw" }
}

resource "aws_route_table" "rt" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }

  tags = { Name = "waf-route-table" }
}

resource "aws_route_table_association" "a" {
  subnet_id      = aws_subnet.a.id
  route_table_id = aws_route_table.rt.id
}

resource "aws_route_table_association" "c" {
  subnet_id      = aws_subnet.c.id
  route_table_id = aws_route_table.rt.id
}

###############################################################################
# 2. SSH Key (TLS → KeyPair)
###############################################################################
resource "tls_private_key" "key" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "aws_key_pair" "generated" {
  key_name   = "dvwa-key"
  public_key = tls_private_key.key.public_key_openssh
}

resource "local_file" "pem" {
  content         = tls_private_key.key.private_key_pem
  filename        = "${path.module}/dvwa-key.pem"
  file_permission = "0400"
}

###############################################################################
# 3. Security Groups
###############################################################################
resource "aws_security_group" "alb" {
  name   = "waf-alb-sg"
  vpc_id = aws_vpc.main.id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "ec2" {
  name   = "waf-ec2-sg"
  vpc_id = aws_vpc.main.id

  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.my_ip]
  }

  ingress {
    description     = "HTTP from ALB"
    from_port       = 80
    to_port         = 80
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

###############################################################################
# 4. EC2 (DVWA)
###############################################################################
data "aws_ssm_parameter" "al2" {
  name = "/aws/service/ami-amazon-linux-latest/amzn2-ami-hvm-x86_64-ebs"
}

resource "aws_instance" "dvwa" {
  ami                    = data.aws_ssm_parameter.al2.value
  instance_type          = "t2.micro"
  subnet_id              = aws_subnet.a.id
  vpc_security_group_ids = [aws_security_group.ec2.id]
  key_name               = aws_key_pair.generated.key_name
  tags                   = { Name = "ec2-dvwa" }
}

###############################################################################
# 5. ALB + Target Group
###############################################################################
resource "aws_lb_target_group" "tg" {
  name        = "waf-tg"
  port        = 80
  protocol    = "HTTP"
  vpc_id      = aws_vpc.main.id
  target_type = "instance"

  health_check {
    path     = "/dvwa/"
    matcher  = "200-399"
    interval = 30
    timeout  = 5
  }
}

resource "aws_lb" "alb" {
  name               = "alb-waf"
  load_balancer_type = "application"
  subnets            = [aws_subnet.a.id, aws_subnet.c.id]
  security_groups    = [aws_security_group.alb.id]
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.alb.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.tg.arn
  }
}

resource "aws_lb_target_group_attachment" "attach" {
  target_group_arn = aws_lb_target_group.tg.arn
  target_id        = aws_instance.dvwa.id
  port             = 80
}

###############################################################################
# 6. 차단용 IPSet
###############################################################################
resource "aws_wafv2_ip_set" "blocklist" {
  name               = "waf-block-ipset"
  scope              = "REGIONAL"
  ip_address_version = "IPV4"
  addresses          = []
}

###############################################################################
# 7. Web ACL (Managed Rules + Blocklist)
###############################################################################
resource "aws_wafv2_web_acl" "waf" {
  name        = "waf-dvwa"
  scope       = "REGIONAL"
  description = "DVWA Web ACL with auto IP block"

  default_action {
    allow {}
  }

  # 블랙리스트 룰 (priority 0)
  rule {
    name     = "blocklist-rule"
    priority = 0

    action {
      block {}
    }

    statement {
      ip_set_reference_statement {
        arn = aws_wafv2_ip_set.blocklist.arn
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      sampled_requests_enabled   = true
      metric_name                = "blocklist"
    }
  }

  # Managed Core Rule (priority 1)
  rule {
    name     = "aws-core"
    priority = 1

    override_action {
      none {}
    }

    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesCommonRuleSet"
        vendor_name = "AWS"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      sampled_requests_enabled   = true
      metric_name                = "core"
    }
  }

  # Managed SQLi Rule (priority 2)
  rule {
    name     = "aws-sqli"
    priority = 2

    override_action {
      none {}
    }

    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesSQLiRuleSet"
        vendor_name = "AWS"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      sampled_requests_enabled   = true
      metric_name                = "sqli"
    }
  }

  visibility_config {
    cloudwatch_metrics_enabled = true
    sampled_requests_enabled   = true
    metric_name                = "waf-dvwa"
  }
}

resource "aws_wafv2_web_acl_association" "assoc" {
  resource_arn = aws_lb.alb.arn
  web_acl_arn  = aws_wafv2_web_acl.waf.arn
}

###############################################################################
# 8. WAF Logging → CloudWatch Logs
###############################################################################
resource "aws_cloudwatch_log_group" "waf_logs" {
  name              = "aws-waf-logs-dvwa"
  retention_in_days = 14
}

resource "aws_wafv2_web_acl_logging_configuration" "logging" {
  resource_arn            = aws_wafv2_web_acl.waf.arn
  log_destination_configs = [aws_cloudwatch_log_group.waf_logs.arn]
}

###############################################################################
# 9. SNS + Metric Alarm
###############################################################################
resource "aws_sns_topic" "sns" {
  name = "sns-waf-alarm"
}

resource "aws_sns_topic_subscription" "email" {
  topic_arn = aws_sns_topic.sns.arn
  protocol  = "email"
  endpoint  = var.alert_email
}

resource "aws_cloudwatch_metric_alarm" "blocked_alarm" {
  alarm_name          = "waf-blocked-count"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 1
  metric_name         = "BlockedRequests"
  namespace           = "AWS/WAFV2"
  period              = 60
  statistic           = "Sum"
  threshold           = 1
  treat_missing_data  = "notBreaching"

  dimensions = {
    WebACL = aws_wafv2_web_acl.waf.name,
    Region = var.aws_region,
    Rule   = "ALL"
  }

  alarm_actions = [aws_sns_topic.sns.arn]
}

###############################################################################
# 10. Lambda (Discord 알림)
###############################################################################
resource "aws_iam_role" "lambda_alert_role" {
  name = "lambda-waf-alert-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Effect = "Allow",
      Principal = { Service = "lambda.amazonaws.com" },
      Action = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "alert_basic" {
  role       = aws_iam_role.lambda_alert_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_lambda_function" "alert" {
  function_name = "lambda-waf-alert"
  filename      = "lambda-alert.zip"
  handler       = "lambda_function.lambda_handler"
  runtime       = "python3.9"
  role          = aws_iam_role.lambda_alert_role.arn
  timeout       = 10

  environment {
    variables = {
      WEBHOOK = var.webhook_url
    }
  }
}

###############################################################################
# 11. Lambda (IP 차단)
###############################################################################
resource "aws_iam_role" "lambda_block_role" {
  name = "lambda-waf-block-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Effect = "Allow",
      Principal = { Service = "lambda.amazonaws.com" },
      Action = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_policy" "waf_write" {
  name = "lambda-waf-update-ipset"

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Effect   = "Allow",
      Action   = ["wafv2:GetIPSet", "wafv2:UpdateIPSet"],
      Resource = aws_wafv2_ip_set.blocklist.arn
    }]
  })
}

resource "aws_iam_role_policy_attachment" "block_basic" {
  role       = aws_iam_role.lambda_block_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy_attachment" "block_waf" {
  role       = aws_iam_role.lambda_block_role.name
  policy_arn = aws_iam_policy.waf_write.arn
}

resource "aws_lambda_function" "block" {
  function_name = "lambda-waf-block"
  filename      = "lambda-block.zip"
  handler       = "lambda_function.lambda_handler"
  runtime       = "python3.9"
  role          = aws_iam_role.lambda_block_role.arn
  timeout       = 10

  environment {
    variables = {
      IPSET_ID   = aws_wafv2_ip_set.blocklist.id
      IPSET_NAME = aws_wafv2_ip_set.blocklist.name
      SCOPE      = "REGIONAL"
    }
  }
}

###############################################################################
# 12. CloudWatch Logs → Lambda 구독
###############################################################################
## 12-1. 모든 로그 → Discord 알림
resource "aws_lambda_permission" "alert_perm" {
  statement_id  = "AllowLogsToAlert"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.alert.function_name
  principal     = "logs.amazonaws.com"
  source_arn    = "${aws_cloudwatch_log_group.waf_logs.arn}:*"
}

resource "aws_cloudwatch_log_subscription_filter" "alert_sub" {
  name            = "waf-to-discord"
  log_group_name  = aws_cloudwatch_log_group.waf_logs.name
  filter_pattern  = ""
  destination_arn = aws_lambda_function.alert.arn
  depends_on      = [aws_lambda_permission.alert_perm]
}

## 12-2. BLOCK 로그만 → IPSet 추가
resource "aws_lambda_permission" "block_perm" {
  statement_id  = "AllowLogsToBlock"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.block.function_name
  principal     = "logs.amazonaws.com"
  source_arn    = "${aws_cloudwatch_log_group.waf_logs.arn}:*"
}

resource "aws_cloudwatch_log_subscription_filter" "block_sub" {
  name            = "waf-to-ipset"
  log_group_name  = aws_cloudwatch_log_group.waf_logs.name
  filter_pattern  = "{ $.action = \"BLOCK\" }"
  destination_arn = aws_lambda_function.block.arn
  depends_on      = [aws_lambda_permission.block_perm]
}
