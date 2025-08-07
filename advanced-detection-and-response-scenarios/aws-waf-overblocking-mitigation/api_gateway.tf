#--------------------------------------
# API Gateway REST API 생성
#--------------------------------------
resource "aws_api_gateway_rest_api" "malware_api" {
  name        = "${var.name_api_gateway}-${random_id.suffix.hex}"
  description = "REST API for GuardDuty malware response Step Functions trigger"

  endpoint_configuration {
    types = ["REGIONAL"]
  }
}

#--------------------------------------
# /malware Resource (POST 엔드포인트)
#--------------------------------------
resource "aws_api_gateway_resource" "malware" {
  rest_api_id = aws_api_gateway_rest_api.malware_api.id
  parent_id   = aws_api_gateway_rest_api.malware_api.root_resource_id
  path_part   = "malware"
}

resource "aws_api_gateway_method" "malware_post" {
  rest_api_id   = aws_api_gateway_rest_api.malware_api.id
  resource_id   = aws_api_gateway_resource.malware.id
  http_method   = "POST"
  authorization = "NONE"
}

#--------------------------------------
# Step Functions Integration: /malware POST → StartExecution
#--------------------------------------
resource "aws_api_gateway_integration" "malware_post_sfn" {
  rest_api_id             = aws_api_gateway_rest_api.malware_api.id
  resource_id             = aws_api_gateway_resource.malware.id
  http_method             = aws_api_gateway_method.malware_post.http_method

  integration_http_method = "POST"
  type                    = "AWS"
  uri                     = "arn:aws:apigateway:${var.aws_region}:states:action/StartExecution"
  credentials             = aws_iam_role.apigw_stepfunction_role.arn

  request_templates = {
    "application/json" = <<EOF
{
  "input": "$util.escapeJavaScript($input.json('$'))",
  "stateMachineArn": "${aws_sfn_state_machine.malware_step.arn}"
}
EOF
  }
  passthrough_behavior = "NEVER"
}

#--------------------------------------
# 메서드 응답 및 통합 응답
#--------------------------------------
resource "aws_api_gateway_method_response" "malware_post_200" {
  rest_api_id = aws_api_gateway_rest_api.malware_api.id
  resource_id = aws_api_gateway_resource.malware.id
  http_method = aws_api_gateway_method.malware_post.http_method
  status_code = "200"
}

resource "aws_api_gateway_integration_response" "malware_post_200" {
  rest_api_id = aws_api_gateway_rest_api.malware_api.id
  resource_id = aws_api_gateway_resource.malware.id
  http_method = aws_api_gateway_method.malware_post.http_method
  status_code = aws_api_gateway_method_response.malware_post_200.status_code

  response_templates = {
    "application/json" = ""
  }
}

#--------------------------------------
# API Gateway 배포 (default Stage)
#--------------------------------------
resource "aws_api_gateway_deployment" "malware_api" {
  rest_api_id = aws_api_gateway_rest_api.malware_api.id
  stage_name  = "default"

  depends_on = [
    aws_api_gateway_integration.malware_post_sfn
  ]
}

#--------------------------------------
# (outputs.tf에서 invoke_url 등 자동조회)
#--------------------------------------
