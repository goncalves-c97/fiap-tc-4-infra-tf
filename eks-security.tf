# ---------------------------------------------------------------------------
# EKS Cluster Security Group
# - Acts as a virtual firewall for the EKS cluster control plane ENIs.
# ---------------------------------------------------------------------------
resource "aws_security_group" "eks_cluster_sg" {
  name        = "eks-cluster-sg"
  description = "Security group for EKS cluster control plane"
  vpc_id      = aws_vpc.this.id

  tags = {
    Name = "eks-cluster-sg"
  }
}

# ---------------------------------------------------------------------------
# Security Group Rule for EKS to RDS Communication
# - Allows outbound traffic from the EKS nodes to the RDS database on the SQL Server port.
# ---------------------------------------------------------------------------
resource "aws_security_group_rule" "eks_to_rds" {
  type                     = "egress"
  from_port                = 1433
  to_port                  = 1433
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.eks_cluster_sg.id
  security_group_id        = aws_security_group.rds_sg.id
  description              = "Allow EKS nodes to connect to RDS"
}
