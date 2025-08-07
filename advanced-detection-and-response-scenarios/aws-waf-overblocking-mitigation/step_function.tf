#--------------------------------------
# Step Functions 상태 머신 정의 (Malware 자동대응 워크플로우)
#--------------------------------------
resource "aws_sfn_state_machine" "malware_step" {
  name     = "${var.name_step_functions}-${random_id.suffix.hex}"
  role_arn = aws_iam_role.step_function_role.arn

  definition = jsonencode({
    Comment = "GuardDuty Malware 자동 대응 워크플로우",
    StartAt = "lambda-isolated-sg",
    States = {
      "lambda-isolated-sg" = {
        Type = "Task",
        Resource = "${aws_lambda_function.lambda_isolated_sg.arn}",
        Parameters = {
          "instance_id.$" = "$.instance_id"
        },
        ResultPath = "$.isolate",
        Next = "lambda-ebs"
      },
      "lambda-ebs" = {
        Type = "Task",
        Resource = "${aws_lambda_function.lambda_ebs.arn}",
        Parameters = {
          "instance_id.$" = "$.isolate.instance_id"
        },
        ResultPath = "$.ebs",
        Next = "lambda-ebs-attach"
      },
      "lambda-ebs-attach" = {
        Type = "Task",
        Resource = "${aws_lambda_function.lambda_ebs_attach.arn}",
        Parameters = {
          "snapshot_id.$" = "$.ebs.snapshot_id"
        },
        ResultPath = "$.attach",
        Next = "lambda-ssm"
      },
      "lambda-ssm" = {
        Type = "Task",
        Resource = "${aws_lambda_function.lambda_ssm.arn}",
        Parameters = {
          "device.$" = "$.attach.device"
        },
        ResultPath = "$.ssm",
        Next = "lambda-s3"
      },
      "lambda-s3" = {
        Type = "Task",
        Resource = "${aws_lambda_function.lambda_s3.arn}",
        Parameters = {
          "command_id.$" = "$.ssm.command_id"
        },
        ResultPath = "$.s3",
        Next = "lambda-discord"
      },
      "lambda-discord" = {
        Type = "Task",
        Resource = "${aws_lambda_function.lambda_discord.arn}",
        Parameters = {
          "instance_id.$" = "$.isolate.instance_id",
          "snapshot_id.$" = "$.ebs.snapshot_id",
          "s3_bucket.$" = "$.s3.s3_bucket",
          "s3_key_prefix.$" = "$.s3.s3_key_prefix",
          "isolation_status.$" = "$.isolate.status"
        },
        ResultPath = "$.discord",
        End = true
      }
    }
  })

  tags = {
    Name    = "${var.name_step_functions}-${random_id.suffix.hex}"
    Purpose = "GuardDuty Malware Response Workflow"
  }
}
