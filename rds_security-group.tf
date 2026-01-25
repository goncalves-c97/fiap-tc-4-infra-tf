resource "aws_security_group" "rds_sg" {
  name        = "rds-sqlserver-security-group"
  description = "Permite acesso ao SQL Server"
  vpc_id      = aws_vpc.tc4-vpc.id # Referência dinâmica ao ID da VPC

  ingress {
    from_port   = 1433
    to_port     = 1433
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}