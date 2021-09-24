##################################################################################
# VARIABLES
##################################################################################
# variable "aws_access_key" {
#     default = ""
# }
# variable "aws_secret_key" {}
variable "aws_region" {
  default = "ap-southeast-2"
}
variable "project_name" {
  default = "terraform-demo"
}
variable "environment" {
  default = "sandbox"
}

##################################################################################
# PROVIDERS
##################################################################################
provider "aws" {
  profile = "default"
  region  = var.aws_region
}

##################################################################################
# DATA
##################################################################################
data "archive_file" "archive_artifacts" {
  type        = "zip"
  source_dir  = "../src/TerraformDemo.WebAPI/bin/Release/netcoreapp3.1/publish"
  output_path = "../dist/${var.project_name}-${var.environment}.zip"
}

##################################################################################
# RESOURCES
##################################################################################
##################################################################################
# 1. LAMBDA
##################################################################################
resource "aws_lambda_function" "main" {
  filename         = "../dist/${var.project_name}-${var.environment}.zip"
  function_name    = "${var.project_name}-${var.environment}-lambda"
  runtime          = "dotnetcore3.1"
  handler          = "TerraformDemo.WebAPI::TerraformDemo.WebAPI.LambdaEntryPoint::FunctionHandlerAsync"
  source_code_hash = filebase64sha256("../dist/${var.project_name}-${var.environment}.zip")
  role             = aws_iam_role.lambda_exec_role.arn
}

resource "aws_iam_role" "lambda_exec_role" {
  name = "${var.project_name}-${var.environment}-lambda-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Sid    = ""
      Principal = {
        Service = "lambda.amazonaws.com"
      }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_basic_exec_policy" {
  role       = aws_iam_role.lambda_exec_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

##################################################################################
# 2. API GATEWAY 
##################################################################################
resource "aws_api_gateway_rest_api" "main" {
  name        = "${var.project_name}-${var.environment}-apigateway"
  description = "TMT medical warnings solution for eMeds"
}

resource "aws_api_gateway_resource" "proxy" {
  rest_api_id = aws_api_gateway_rest_api.main.id
  parent_id   = aws_api_gateway_rest_api.main.root_resource_id
  path_part   = "{proxy+}"
}

resource "aws_api_gateway_method" "proxy" {
  rest_api_id   = aws_api_gateway_rest_api.main.id
  resource_id   = aws_api_gateway_resource.proxy.id
  http_method   = "ANY"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "lambda" {
  rest_api_id = aws_api_gateway_rest_api.main.id
  resource_id = aws_api_gateway_method.proxy.resource_id
  http_method = aws_api_gateway_method.proxy.http_method

  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.main.invoke_arn
}

resource "aws_api_gateway_method" "proxy_root" {
  rest_api_id   = aws_api_gateway_rest_api.main.id
  resource_id   = aws_api_gateway_rest_api.main.root_resource_id
  http_method   = "ANY"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "lambda_root" {
  rest_api_id = aws_api_gateway_rest_api.main.id
  resource_id = aws_api_gateway_method.proxy_root.resource_id
  http_method = aws_api_gateway_method.proxy_root.http_method

  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.main.invoke_arn
}

resource "aws_api_gateway_deployment" "example" {
  depends_on = [
    aws_api_gateway_integration.lambda,
    aws_api_gateway_integration.lambda_root,
  ]

  rest_api_id = aws_api_gateway_rest_api.main.id
}

resource "aws_api_gateway_stage" "main" {
  deployment_id = aws_api_gateway_deployment.example.id
  rest_api_id   = aws_api_gateway_rest_api.main.id
  stage_name    = var.environment
}

resource "aws_lambda_permission" "apigw_root" {
  statement_id  = "AllowAPIGatewayProxyInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.main.function_name
  principal     = "apigateway.amazonaws.com"

  source_arn = "${aws_api_gateway_rest_api.main.execution_arn}/*/*/"
}

resource "aws_lambda_permission" "apigw_proxy" {
  statement_id  = "AllowAPIGatewayRootInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.main.function_name
  principal     = "apigateway.amazonaws.com"

  source_arn = "${aws_api_gateway_rest_api.main.execution_arn}/*/*/*"
}