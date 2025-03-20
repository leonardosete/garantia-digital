terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
  # Caso use o backend remoto (S3) num arquivo "backend.tf", não repita aqui
}

provider "aws" {
  region = "us-east-1"
}

variable "lambda_version" {
  type        = string
  description = "Versão para o nome do Lambda"
}

variable "email_smtp" {
  type      = string
  sensitive = true
}

variable "pass_smtp" {
  type      = string
  sensitive = true
}

resource "aws_lambda_function" "garantia_digital" {
  function_name = "garantia-digital-${replace(var.lambda_version, ".", "-")}"
  # Use a role ARN criada no script bash
  role          = "arn:aws:iam::114284751948:role/LambdaGarantiaDigitalRole"
  
  runtime       = "python3.9"
  handler       = "create-garantia.lambda_handler"
  filename      = "../lambda_function_payload.zip"

  source_code_hash = filebase64sha256("../lambda_function_payload.zip")

  environment {
    variables = {
      email_smtp = var.email_smtp
      pass_smtp  = var.pass_smtp
    }
  }
}
