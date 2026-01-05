terraform {
  backend "s3" {
    bucket = "fiap-terraform-backend-infra-tf"
    key    = "tc4/infra/terraform.tfstate"
    region = "us-east-1" 
  }
}
