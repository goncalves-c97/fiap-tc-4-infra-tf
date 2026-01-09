variable "aws_region" {
  description = "A região AWS preferida para a criação dos recursos."
  type        = string
  default     = "us-east-1"
}

variable "public_subnet_cidr" {
  type    = string
  default = "10.0.1.0/24"
}

variable "private_subnet_a_cidr" {
  type    = string
  default = "10.0.2.0/24"
}

variable "private_subnet_b_cidr" {
  type    = string
  default = "10.0.3.0/24"
}

variable "vpc_cidr" {
  type    = string
  default = "10.0.0.0/16"
}
