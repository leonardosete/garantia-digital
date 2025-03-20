terraform {
  backend "s3" {
    bucket         = "garantia-digital-terraform-state"
    key            = "terraform.tfstate"
    region         = "us-east-1"
    encrypt        = true
  }
}
