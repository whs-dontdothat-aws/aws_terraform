#--------------------------------------
# 랜덤 suffix 생성 (다른 tf 파일에서 이미 선언되어 있으면 여기 생략/중복 X)
#--------------------------------------
resource "random_id" "suffix" {
  byte_length = var.random_suffix_length
}

#--------------------------------------
# EC2 SSM 분석/명령 실행용 Role, Policy, Profile
#--------------------------------------
resource "aws_iam_role" "ec2_ssm_role" {
  name = "${var.name_iam_ec2_ssm_role}-${random_id.suffix.hex}"
  assume_role_policy = data.aws_iam_policy_document.ec2_ssm_assume_role.json
  tags = {
    Name = "${var.name_iam_ec2_ssm_role}-${random_id.suffix.hex}"
  }
}

data "aws_iam_policy_document" "ec2_ssm_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role_policy_attachment" "ec2_ssm_managed" {
  role       = aws_iam_role.ec2_ssm_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_policy" "ec2_ssm_s3_write" {
  name        = "EC2WriteS3-${random_id.suffix.hex}"
  description = "Allow EC2 SSM role to write analysis logs to S3 logarchive"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["s3:PutObject"]
      Resource = "${aws_s3_bucket.logarchive.arn}/*"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "ec2_ssm_s3_write_attach" {
  role       = aws_iam_role.ec2_ssm_role.name
  policy_arn = aws_iam_policy.ec2_ssm_s3_write.arn
}


/*
#--------------------------------------
# Sumo Logic S3 접근용 Role and Policy
# Account/External ID는 Sumo Logic 연동 설정값 반영
#--------------------------------------
resource "aws_iam_role" "sumologic_role" {
  name = "${var.name_iam_sumologic_role}-${random_id.suffix.hex}"
  assume_role_policy = data.aws_iam_policy_document.sumologic_assume.json
  tags = {
    Name = "${var.name_iam_sumologic_role}-${random_id.suffix.hex}"
  }
}

data "aws_iam_policy_document" "sumologic_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "AWS"
      identifiers = ["arn:aws:iam::<SUMO_ACCOUNT_ID>:root"] # 실제 값 입력
    }
    condition {
      test     = "StringEquals"
      variable = "sts:ExternalId"
      values   = ["<SUMO_LOGIC_EXTERNAL_ID>"] # 실제 값 입력
    }
  }
}

resource "aws_iam_policy" "sumologic_s3_policy" {
  name = "policy-s3-sumologic-guardduty-events-${random_id.suffix.hex}"
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Effect = "Allow",
      Action = [
        "s3:GetObject",
        "s3:GetObjectVersion",
        "s3:ListBucket"
      ],
      Resource = [
        "${aws_s3_bucket.guardduty_events.arn}",
        "${aws_s3_bucket.guardduty_events.arn}/*"
      ]
    }]
  })
}

resource "aws_iam_role_policy_attachment" "sumologic_s3_attach" {
  role       = aws_iam_role.sumologic_role.name
  policy_arn = aws_iam_policy.sumologic_s3_policy.arn
}

*/

#--------------------------------------
# Lambda별 실행 Role/Policy (주요 대표 예시)
# 함수별 역할/정책 패턴은 아래와 같이 확장 사용
#--------------------------------------

resource "aws_iam_role" "lambda_isolated_sg_role" {
  name = "lambda-isolated-sg-role-${random_id.suffix.hex}"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume.json
}

resource "aws_iam_role" "lambda_ebs_role" {
  name = "lambda-ebs-role-${random_id.suffix.hex}"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume.json
}

resource "aws_iam_role" "lambda_ebs_attach_role" {
  name = "lambda-ebs-attach-role-${random_id.suffix.hex}"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume.json
}

resource "aws_iam_role" "lambda_ssm_role" {
  name = "lambda-ssm-role-${random_id.suffix.hex}"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume.json
}

resource "aws_iam_role" "lambda_s3_role" {
  name = "lambda-s3-role-${random_id.suffix.hex}"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume.json
}

resource "aws_iam_role" "lambda_discord_role" {
  name = "lambda-discord-role-${random_id.suffix.hex}"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume.json
}

data "aws_iam_policy_document" "lambda_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

# 실제 정책은 각 Lambda 기능에 맞는 최소 권한 부여!
resource "aws_iam_policy" "lambda_isolated_sg_policy" {
  name   = "lambda-isolated-sg-policy-${random_id.suffix.hex}"
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect   = "Allow",
        Action   = [
          "ec2:DescribeInstances", 
          "ec2:ModifyInstanceAttribute",
          "ec2:ModifyNetworkInterfaceAttribute"
        ],
        Resource = "*"
      },
      {
        Effect = "Allow",
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ],
        Resource = "arn:aws:logs:*:*:*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_isolated_sg_attach" {
  role       = aws_iam_role.lambda_isolated_sg_role.name
  policy_arn = aws_iam_policy.lambda_isolated_sg_policy.arn
}

# (아래는 대표 패턴이니 각 Lambda별 필요한 EC2, SSM, S3, SNS 등 최소권한 정책으로 개별 작성 필요!)

#--------------------------------------
# Step Functions 실행/연동용 IAM Role/Policy
#--------------------------------------
resource "aws_iam_role" "step_function_role" {
  name = "step-functions-role-${random_id.suffix.hex}"
  assume_role_policy = data.aws_iam_policy_document.step_func_assume.json
}

data "aws_iam_policy_document" "step_func_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["states.amazonaws.com"]
    }
  }
}

resource "aws_iam_policy" "step_function_lambda_invoke" {
  name = "step-func-lambda-invoke-${random_id.suffix.hex}"
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Effect = "Allow",
      Action = [
        "lambda:InvokeFunction"
      ],
      Resource = [
        aws_lambda_function.lambda_isolated_sg.arn,
        aws_lambda_function.lambda_ebs.arn,
        aws_lambda_function.lambda_ebs_attach.arn,
        aws_lambda_function.lambda_ssm.arn,
        aws_lambda_function.lambda_s3.arn,
        aws_lambda_function.lambda_discord.arn,
        aws_lambda_function.lambda_upload_findings_to_s3.arn
      ]
    }]
  })
}

resource "aws_iam_role_policy_attachment" "step_func_lambda_invoke_attach" {
  role       = aws_iam_role.step_function_role.name
  policy_arn = aws_iam_policy.step_function_lambda_invoke.arn
}

#--------------------------------------
# API Gateway가 Step Functions 실행하는 IAM Role/Policy
#--------------------------------------
resource "aws_iam_role" "apigw_stepfunction_role" {
  name = "malware-APIGW-Role-${random_id.suffix.hex}"
  assume_role_policy = data.aws_iam_policy_document.apigw_assume.json
}

data "aws_iam_policy_document" "apigw_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["apigateway.amazonaws.com"]
    }
  }
}

resource "aws_iam_policy" "apigw_stepfunction_policy" {
  name = "apigw-stepfunction-policy-${random_id.suffix.hex}"
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Effect = "Allow",
      Action = ["states:StartExecution"],
      Resource = aws_sfn_state_machine.malware_step.arn
    }]
  })
}

resource "aws_iam_role_policy_attachment" "apigw_stepfunc_attach" {
  role       = aws_iam_role.apigw_stepfunction_role.name
  policy_arn = aws_iam_policy.apigw_stepfunction_policy.arn
}

# IAM Role for lambda-upload-findings-to-s3
#--------------------------------------
resource "aws_iam_role" "lambda_upload_findings_to_s3_role" {
  name = "lambda-upload-findings-to-s3-role-${random_id.suffix.hex}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Effect = "Allow",
      Principal = { Service = "lambda.amazonaws.com" },
      Action   = "sts:AssumeRole"
    }]
  })
}

# S3에 객체 쓰기 권한 (필요 최소 권한)
resource "aws_iam_policy" "lambda_upload_findings_to_s3_policy" {
  name        = "lambda-upload-findings-to-s3-policy-${random_id.suffix.hex}"
  description = "Allow Lambda to write GuardDuty findings to S3"

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      # 버킷 내 특정 프리픽스에 PutObject
      {
        Sid    = "PutObjectsToBucket"
        Effect = "Allow"
        Action = [
          "s3:PutObject",
          "s3:AbortMultipartUpload"
        ]
        Resource = "${aws_s3_bucket.guardduty_events.arn}/guardduty/finding-logs/*"
      },
      # 선택: ListBucket(프리픽스 제한) 및 GetBucketLocation (멀티파트 등 일부 SDK 동작 시 필요)
      {
        Sid    = "ListBucketWithPrefix"
        Effect = "Allow"
        Action = [
          "s3:ListBucket",
          "s3:GetBucketLocation"
        ]
        Resource = aws_s3_bucket.guardduty_events.arn
        Condition = {
          StringLike = {
            "s3:prefix" = "guardduty/finding-logs/*"
          }
        }
      }
    ]
  })
}

# 커스텀 S3 정책 부여
resource "aws_iam_role_policy_attachment" "attach_s3_policy" {
  role       = aws_iam_role.lambda_upload_findings_to_s3_role.name
  policy_arn = aws_iam_policy.lambda_upload_findings_to_s3_policy.arn
}

# CloudWatch Logs 권한 (관리형 정책)
resource "aws_iam_role_policy_attachment" "attach_basic_logs" {
  role       = aws_iam_role.lambda_upload_findings_to_s3_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# lambda-ebs가 EC2 메타데이터를 조회하기 위한 읽기 전용 정책
resource "aws_iam_policy" "lambda_ebs_ec2_read" {
  name   = "lambda-ebs-ec2-read-${random_id.suffix.hex}"
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect   = "Allow",
        Action   = [
          "ec2:DescribeInstances",
          "ec2:DescribeTags",
          "ec2:DescribeVolumes",
          "ec2:DescribeSnapshots",
          "ec2:DescribeAvailabilityZones"
        ],
        Resource = "*"
      }
    ]
  })
}

# 위 정책을 lambda_ebs_role에 부착
resource "aws_iam_role_policy_attachment" "lambda_ebs_ec2_read_attach" {
  role       = aws_iam_role.lambda_ebs_role.name
  policy_arn = aws_iam_policy.lambda_ebs_ec2_read.arn
}

# (권장) Lambda 기본 로그 권한 부여 - CloudWatch Logs
resource "aws_iam_role_policy_attachment" "lambda_ebs_logs_basic" {
  role       = aws_iam_role.lambda_ebs_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_policy" "lambda_ebs_attach_ec2_ctrl" {
  name   = "lambda-ebs-attach-ec2-ctrl-${random_id.suffix.hex}"
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Action = [
          "ec2:AttachVolume",
          "ec2:DetachVolume",
          "ec2:DescribeInstances",
          "ec2:DescribeVolumes",
          "ec2:DescribeVolumeStatus",
          "ec2:DescribeAvailabilityZones"
        ],
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_ebs_attach_ctrl_attach" {
  role       = aws_iam_role.lambda_ebs_attach_role.name
  policy_arn = aws_iam_policy.lambda_ebs_attach_ec2_ctrl.arn
}

resource "aws_iam_role_policy_attachment" "lambda_ebs_attach_logs_basic" {
  role       = aws_iam_role.lambda_ebs_attach_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_policy" "lambda_ebs_ec2_write" {
  name   = "lambda-ebs-ec2-write-${random_id.suffix.hex}"
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      # 스냅샷 생성/태깅
      {
        Effect   = "Allow",
        Action   = [
          "ec2:CreateSnapshot",
          "ec2:CreateTags"
        ],
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_ebs_ec2_write_attach" {
  role       = aws_iam_role.lambda_ebs_role.name
  policy_arn = aws_iam_policy.lambda_ebs_ec2_write.arn
}

resource "aws_iam_policy" "lambda_ebs_attach_read" {
  name   = "lambda-ebs-attach-read-${random_id.suffix.hex}"
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Action = [
          "ec2:DescribeSnapshots",
          "ec2:CreateVolume",
           "ec2:CreateTags"
        ],
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_ebs_attach_read_attach" {
  role       = aws_iam_role.lambda_ebs_attach_role.name
  policy_arn = aws_iam_policy.lambda_ebs_attach_read.arn
}

data "aws_region" "current" {}
data "aws_caller_identity" "current" {}

resource "aws_iam_policy" "lambda_ssm_invoke" {
  name   = "lambda-ssm-invoke-${random_id.suffix.hex}"
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Action = ["ssm:SendCommand"],
        Resource = [
          # 대상 EC2 인스턴스(계정 소유)
          "arn:aws:ec2:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:instance/*",

          # (중요) AWS 관리 문서
          "arn:aws:ssm:${data.aws_region.current.name}::document/AWS-RunShellScript",

          # 필요 시 다른 AWS 관리 문서도 추가
          # "arn:aws:ssm:${data.aws_region.current.name}::document/AWS-RunPowerShellScript",

          # 계정 소유 커스텀 문서를 쓸 수도 있으면 이것도 포함
          "arn:aws:ssm:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:document/*"
        ]
      },
      {
        Effect = "Allow",
        Action = [
          "ssm:GetCommandInvocation",
          "ssm:ListCommandInvocations",
          "ssm:ListCommands"
        ],
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_ssm_invoke_attach" {
  role       = aws_iam_role.lambda_ssm_role.name
  policy_arn = aws_iam_policy.lambda_ssm_invoke.arn
}

resource "aws_iam_policy" "lambda_s3_ssm_invoke" {
  name   = "lambda-s3-ssm-invoke-${random_id.suffix.hex}"
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Action = ["ssm:SendCommand"],
        Resource = [
          # 대상 EC2 인스턴스(자기 계정)
          "arn:aws:ec2:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:instance/*",
          # (중요) AWS 관리 문서는 계정 ID가 비어 있음
          "arn:aws:ssm:${data.aws_region.current.name}::document/AWS-RunShellScript",
          # 필요 시 계정 소유 커스텀 문서도 허용
          "arn:aws:ssm:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:document/*"
        ]
      },
      {
        Effect = "Allow",
        Action = [
          "ssm:GetCommandInvocation",
          "ssm:ListCommandInvocations",
          "ssm:ListCommands"
        ],
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_s3_ssm_invoke_attach" {
  role       = aws_iam_role.lambda_s3_role.name
  policy_arn = aws_iam_policy.lambda_s3_ssm_invoke.arn
}

# (권장) CloudWatch Logs 기본 권한
resource "aws_iam_role_policy_attachment" "lambda_s3_logs_basic" {
  role       = aws_iam_role.lambda_s3_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}
