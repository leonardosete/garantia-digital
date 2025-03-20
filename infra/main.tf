terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
  # Se tiver o arquivo backend.tf para S3 remoto, não precisa repetir aqui
}

provider "aws" {
  region = "us-east-1"
}

resource "aws_iam_role" "lambda_role" {
  name               = "garantia-digital-lambda-role"
  assume_role_policy = data.aws_iam_policy_document.lambda_trust_policy.json
}

data "aws_iam_policy_document" "lambda_trust_policy" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role_policy_attachment" "lambda_basic_execution" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_lambda_function" "garantia_digital" {
  function_name = "garantia-digital-${replace(var.lambda_version, ".", "-")}"
  role          = aws_iam_role.lambda_role.arn
  runtime       = "python3.9"
  handler       = "create-garantia.lambda_handler"
  filename      = "../lambda_function_payload.zip" # ZIP gerado pelo CI

  # Garante que o arquivo modificado gere um novo deploy
  source_code_hash = filebase64sha256("../lambda_function_payload.zip")

  environment {
    variables = {
      email_smtp = var.email_smtp
      pass_smtp  = var.pass_smtp
      # Aqui vão outras env vars que você precisar
    }
  }
}
