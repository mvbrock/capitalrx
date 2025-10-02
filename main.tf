provider "aws" {
  region = "us-west-1"
}

resource "aws_iam_role" "pricing_demo" {
  name = "lambda_pricing"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = {
        Service = "lambda.amazonaws.com"
      }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "pricing_demo_eni_attachment" {
  role       = aws_iam_role.pricing_demo.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
}

resource "aws_vpc" "pricing_demo" {
  cidr_block           = "172.16.0.0/18"
  enable_dns_hostnames = true
  enable_dns_support   = true
}

resource "aws_internet_gateway" "pricing_demo" {
  vpc_id = aws_vpc.pricing_demo.id
}

data "aws_availability_zones" "available" {}

resource "aws_subnet" "pricing_demo" {
  vpc_id = aws_vpc.pricing_demo.id
  cidr_block = cidrsubnet(aws_vpc.pricing_demo.cidr_block, 8, 0)
  availability_zone = data.aws_availability_zones.available.names[0]

  tags = {
    Name = "${data.aws_availability_zones.available.names[0]}_pricing_demo"
  }
}

resource "aws_route_table" "pricing_demo" {
  vpc_id = aws_vpc.pricing_demo.id
}

resource "aws_route_table_association" "pricing_demo" {
  depends_on = [aws_subnet.pricing_demo]

  subnet_id      = aws_subnet.pricing_demo.id
  route_table_id = aws_route_table.pricing_demo.id
}

resource "aws_security_group" "pricing_demo" {
  name        = "pricing_demo"
  description = "pricing_demo"
  vpc_id      = aws_vpc.pricing_demo.id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_lambda_function" "pricing_demo" {
  function_name = "lambda_pricing"
  role          = aws_iam_role.pricing_demo.arn
  handler       = "pricing.handler"
  runtime       = "python3.12"
  filename      = "${path.module}/pricing.zip"
  environment {
    variables = {
      SEED = 20251002
    }
  }
}

resource "aws_lambda_function_url" "pricing_demo" {
  function_name      = aws_lambda_function.pricing_demo.function_name
  authorization_type = "NONE"
}

resource "aws_lambda_permission" "allow_public_url" {
  statement_id  = "AllowPublicAccess"
  action        = "lambda:InvokeFunctionUrl"
  function_name = aws_lambda_function.pricing_demo.function_name
  principal     = "*"
  function_url_auth_type = "NONE"
}

resource "aws_cloudwatch_log_group" "pricing_demo" {
  name              = "/aws/lambda/${aws_lambda_function.pricing_demo.function_name}"
}

resource "aws_cloudwatch_metric_alarm" "pricing_demo" {
  alarm_name          = "lambda-invocation-errors"
  namespace           = "AWS/Lambda"
  metric_name         = "Errors"
  dimensions = {
    FunctionName = aws_lambda_function.pricing_demo.function_name
  }

  statistic           = "Sum"
  period              = 60
  evaluation_periods  = 1
  threshold           = 1
  comparison_operator = "GreaterThanOrEqualToThreshold"
  treat_missing_data  = "notBreaching"
}
