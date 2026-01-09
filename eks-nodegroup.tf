# ---------------------------------------------------------------------------
# EKS Node Group IAM Role
# - Allows EC2 nodes to connect to the EKS cluster and manage resources.
# - Trusts the EC2 service principal to assume this role.
# - Attaches required policies:
#   - AmazonEKSWorkerNodePolicy: Core permissions for node operation.
#   - AmazonEC2ContainerRegistryReadOnly: Allows pulling images from ECR.
#   - AmazonEKS_CNI_Policy: Permissions for the AWS VPC CNI plugin to manage networking.
# ---------------------------------------------------------------------------
resource "aws_iam_role" "eks_nodegroup_role" {
  name = "eks-nodegroup-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Principal = {
          Service = "ec2.amazonaws.com"
        },
        Action = "sts:AssumeRole"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "eks_worker_node_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
  role       = aws_iam_role.eks_nodegroup_role.name
}

resource "aws_iam_role_policy_attachment" "eks_cni_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
  role       = aws_iam_role.eks_nodegroup_role.name
}

resource "aws_iam_role_policy_attachment" "ec2_container_registry_read_only" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
  role       = aws_iam_role.eks_nodegroup_role.name
}

# ---------------------------------------------------------------------------
# EKS Managed Node Group
# - Provisions and manages the EC2 instances (worker nodes) for the cluster.
# - Deploys nodes into the private subnets for security.
# - Uses the IAM role created above to grant necessary permissions.
# - Defines scaling configuration for the node group.
# ---------------------------------------------------------------------------
resource "aws_eks_node_group" "this" {
  cluster_name    = aws_eks_cluster.this.name
  node_group_name = "fiap-eks-nodegroup"
  node_role_arn   = aws_iam_role.eks_nodegroup_role.arn
  subnet_ids = [
    aws_subnet.private_a.id,
    aws_subnet.private_b.id
  ]

  instance_types = ["t3.medium"]

  scaling_config {
    desired_size = 4
    max_size     = 8
    min_size     = 1
  }

  update_config {
    max_unavailable = 1
  }

  depends_on = [
    aws_iam_role_policy_attachment.eks_worker_node_policy,
    aws_iam_role_policy_attachment.eks_cni_policy,
    aws_iam_role_policy_attachment.ec2_container_registry_read_only,
  ]

  tags = {
    Name = "fiap-eks-nodegroup"
  }
}
