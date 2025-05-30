terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

#--- VPC & Networking -----------------------------------------------------------------

resource "aws_vpc" "main" {
  cidr_block = "10.0.0.0/16"
  tags = { Name = "demo-vpc" }
}

data "aws_availability_zones" "azs" {}

resource "aws_subnet" "public" {
  count                   = 2
  vpc_id                  = aws_vpc.main.id
  cidr_block              = cidrsubnet(aws_vpc.main.cidr_block, 8, count.index)
  availability_zone       = data.aws_availability_zones.azs.names[count.index]
  map_public_ip_on_launch = true
  tags = { Name = "public-${count.index}" }
}

resource "aws_security_group" "lambda_sg" {
  name        = "lambda-sg"
  description = "Allow all outbound"
  vpc_id      = aws_vpc.main.id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

#--- S3 Bucket -------------------------------------------------------------------------

resource "aws_s3_bucket" "shared" {
  bucket = "tf-demo-shared-bucket-${random_id.bucket_id.hex}"
  acl    = "private"
}

resource "random_id" "bucket_id" {
  byte_length = 4
}

#--- IAM Role for Lambdas --------------------------------------------------------------

data "aws_iam_policy_document" "lambda_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "lambda_exec" {
  name               = "demo-lambda-role"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume.json
}

resource "aws_iam_role_policy_attachment" "lambda_basic" {
  role       = aws_iam_role.lambda_exec.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy" "s3_write" {
  name   = "lambda-s3-write"
  role   = aws_iam_role.lambda_exec.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action   = ["s3:PutObject"]
      Effect   = "Allow"
      Resource = "${aws_s3_bucket.shared.arn}/*"
    }]
  })
}

#--- Package each Lambda ---------------------------------------------------------------

data "archive_file" "lambda1" {
  type        = "zip"
  source_file = "${path.module}/lambda/lambda1/index.py"
  output_path = "${path.module}/lambda1.zip"
}
data "archive_file" "lambda2" {
  type        = "zip"
  source_file = "${path.module}/lambda/lambda2/index.py"
  output_path = "${path.module}/lambda2.zip"
}
data "archive_file" "lambda3" {
  type        = "zip"
  source_file = "${path.module}/lambda/lambda3/index.py"
  output_path = "${path.module}/lambda3.zip"
}
data "archive_file" "lambda4" {
  type        = "zip"
  source_file = "${path.module}/lambda/lambda4/index.py"
  output_path = "${path.module}/lambda4.zip"
}

#--- Define Lambdas --------------------------------------------------------------------

locals {
  names = ["lambda1","lambda2","lambda3","lambda4"]
}

resource "aws_lambda_function" "functions" {
  for_each = toset(local.names)

  function_name = each.key
  role          = aws_iam_role.lambda_exec.arn
  handler       = "index.handler"
  runtime       = "python3.9"
  filename      = "${path.module}/${each.key}.zip"

  vpc_config {
    subnet_ids         = aws_subnet.public[*].id
    security_group_ids = [aws_security_group.lambda_sg.id]
  }

  environment {
    variables = {
      BUCKET = aws_s3_bucket.shared.bucket
    }
  }
}

#--- API Gateways ----------------------------------------------------------------------

resource "aws_apigatewayv2_api" "api1" {
  name          = "api1"
  protocol_type = "HTTP"
}

resource "aws_apigatewayv2_api" "api2" {
  name          = "api2"
  protocol_type = "HTTP"
}

# Integrations & Routes for api1 → lambda1, lambda2

resource "aws_apigatewayv2_integration" "api1_lambda1" {
  api_id                = aws_apigatewayv2_api.api1.id
  integration_type      = "AWS_PROXY"
  integration_uri       = aws_lambda_function.functions["lambda1"].invoke_arn
  payload_format_version = "2.0"
}

resource "aws_apigatewayv2_route" "api1_r1" {
  api_id    = aws_apigatewayv2_api.api1.id
  route_key = "GET /lambda1"
  target    = "integrations/${aws_apigatewayv2_integration.api1_lambda1.id}"
}

resource "aws_lambda_permission" "api1_lambda1" {
  statement_id  = "AllowAPIG1L1"
  action        = "lambda:InvokeFunction"
  principal     = "apigateway.amazonaws.com"
  function_name = aws_lambda_function.functions["lambda1"].function_name
  source_arn    = "${aws_apigatewayv2_api.api1.execution_arn}/*/*"
}

resource "aws_apigatewayv2_integration" "api1_lambda2" {
  api_id                = aws_apigatewayv2_api.api1.id
  integration_type      = "AWS_PROXY"
  integration_uri       = aws_lambda_function.functions["lambda2"].invoke_arn
  payload_format_version = "2.0"
}

resource "aws_apigatewayv2_route" "api1_r2" {
  api_id    = aws_apigatewayv2_api.api1.id
  route_key = "GET /lambda2"
  target    = "integrations/${aws_apigatewayv2_integration.api1_lambda2.id}"
}

resource "aws_lambda_permission" "api1_lambda2" {
  statement_id  = "AllowAPIG1L2"
  action        = "lambda:InvokeFunction"
  principal     = "apigateway.amazonaws.com"
  function_name = aws_lambda_function.functions["lambda2"].function_name
  source_arn    = "${aws_apigatewayv2_api.api1.execution_arn}/*/*"
}

resource "aws_apigatewayv2_stage" "api1_stage" {
  api_id      = aws_apigatewayv2_api.api1.id
  name        = "$default"
  auto_deploy = true
}

# Integrations & Routes for api2 → lambda3, lambda4

resource "aws_apigatewayv2_integration" "api2_lambda3" {
  api_id                = aws_apigatewayv2_api.api2.id
  integration_type      = "AWS_PROXY"
  integration_uri       = aws_lambda_function.functions["lambda3"].invoke_arn
  payload_format_version = "2.0"
}

resource "aws_apigatewayv2_route" "api2_r1" {
  api_id    = aws_apigatewayv2_api.api2.id
  route_key = "GET /lambda3"
  target    = "integrations/${aws_apigatewayv2_integration.api2_lambda3.id}"
}

resource "aws_lambda_permission" "api2_lambda3" {
  statement_id  = "AllowAPIG2L3"
  action        = "lambda:InvokeFunction"
  principal     = "apigateway.amazonaws.com"
  function_name = aws_lambda_function.functions["lambda3"].function_name
  source_arn    = "${aws_apigatewayv2_api.api2.execution_arn}/*/*"
}

resource "aws_apigatewayv2_integration" "api2_lambda4" {
  api_id                = aws_apigatewayv2_api.api2.id
  integration_type      = "AWS_PROXY"
  integration_uri       = aws_lambda_function.functions["lambda4"].invoke_arn
  payload_format_version = "2.0"
}

resource "aws_apigatewayv2_route" "api2_r2" {
  api_id    = aws_apigatewayv2_api.api2.id
  route_key = "GET /lambda4"
  target    = "integrations/${aws_apigatewayv2_integration.api2_lambda4.id}"
}

resource "aws_lambda_permission" "api2_lambda4" {
  statement_id  = "AllowAPIG2L4"
  action        = "lambda:InvokeFunction"
  principal     = "apigateway.amazonaws.com"
  function_name = aws_lambda_function.functions["lambda4"].function_name
  source_arn    = "${aws_apigatewayv2_api.api2.execution_arn}/*/*"
}

resource "aws_apigatewayv2_stage" "api2_stage" {
  api_id      = aws_apigatewayv2_api.api2.id
  name        = "$default"
  auto_deploy = true
}
