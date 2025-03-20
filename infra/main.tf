terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = "us-east-1"
}

resource "aws_lambda_function" "garantia_digital" {
  # Usa a var.lambda_version, mas NÃO a declara aqui
  function_name = "garantia-digital-${replace(var.lambda_version, ".", "-")}"

  # Substitua esse ARN pela role do Lambda já existente
  role = "arn:aws:iam::114284751948:role/LambdaGarantiaDigitalRole"
  runtime  = "python3.9"
  handler  = "create-garantia.lambda_handler"
  filename = "../lambda_function_payload.zip"
  timeout  = 10
  source_code_hash = filebase64sha256("../lambda_function_payload.zip")
}
