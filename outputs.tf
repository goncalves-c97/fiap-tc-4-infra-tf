output "vpc_id" {
  value = aws_vpc.this.id
}

output "public_subnet_id" {
  value = aws_subnet.public.id
}

output "private_subnet_a_id" {
  value = aws_subnet.private_a.id
}

output "private_subnet_b_id" {
  value = aws_subnet.private_b.id
}

output "private_subnet_ids" {
  value = [aws_subnet.private_a.id, aws_subnet.private_b.id]
}

output "nat_gateway_id" {
  value = aws_nat_gateway.gw.id
}

output "rds_subnet_group" {
  value = aws_db_subnet_group.rds_subnet_group.name
}

output "rds_security_group_id" {
  value = aws_security_group.rds_sg.id
}

output "mongodbatlas_subnet_group" {
  value = aws_db_subnet_group.rds_subnet_group.name
}
