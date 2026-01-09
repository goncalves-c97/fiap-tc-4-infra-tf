terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.92"
    }
    mongodbatlas = {
      source  = "mongodb/mongodbatlas",
      version = "~> 2.0"

    }
  }

  required_version = ">= 1.2"
}

provider "aws" {
  region = var.aws_region
}