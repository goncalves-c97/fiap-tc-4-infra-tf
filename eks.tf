# ---------------------------------------------------------------------------
# EKS Cluster IAM Role
# - Grants EKS control plane permission to manage AWS resources on your behalf
#   (e.g., creating ENIs for pods, managing load balancers).
# - Trusts the EKS service principal (eks.amazonaws.com) to assume this role.
# - Attaches the AmazonEKSClusterPolicy managed policy for standard permissions.
# ---------------------------------------------------------------------------
resource "aws_iam_role" "eks_cluster_role" {
  name = "eks-cluster-role"

  assume_role_policy = jsonencode({
    Version   = "2012-10-17",
    Statement = [
      {
        Effect    = "Allow",
        Principal = {
          Service = "eks.amazonaws.com"
        },
        Action    = "sts:AssumeRole"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "eks_cluster_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
  role       = aws_iam_role.eks_cluster_role.name
}

# ---------------------------------------------------------------------------
# EKS Cluster
# - Defines the Kubernetes control plane.
# - Uses the VPC and private subnets from the remote network state.
# - Associates the cluster with the IAM role created above.
# - Enables control plane logging for auditing and debugging.
# ---------------------------------------------------------------------------
resource "aws_eks_cluster" "this" {
  name     = "fiap-eks-cluster"
  role_arn = aws_iam_role.eks_cluster_role.arn

  vpc_config {
    subnet_ids = [
      aws_subnet.private_a.id,
      aws_subnet.private_b.id
    ]
    # Restrict API endpoint access to within your VPC for enhanced security
    endpoint_private_access = true
    endpoint_public_access  = true
  }

  enabled_cluster_log_types = ["api", "audit", "authenticator", "controllerManager", "scheduler"]

  depends_on = [
    aws_iam_role_policy_attachment.eks_cluster_policy
  ]

  tags = {
    Name = "fiap-eks-cluster"
  }
}
