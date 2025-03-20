variable "lambda_version" {
  type        = string
  description = "Versão da função Lambda"
}

variable "email_smtp" {
  type        = string
  description = "Usuário de email SMTP"
  sensitive   = true
}

variable "pass_smtp" {
  type        = string
  description = "Senha do email SMTP"
  sensitive   = true
}
