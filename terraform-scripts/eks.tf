resource "aws_eks_cluster" "this" {
  name                      = "${var.project}-eks"
  enabled_cluster_log_types = ["api", "audit", "authenticator", "controllerManager", "scheduler"]
  role_arn                  = aws_iam_role.eks_cluster_role.arn

  vpc_config {
    subnet_ids             = concat(aws_subnet.public[*].id, aws_subnet.private[*].id)
    # endpoint_public_access = true
    endpoint_private_access = true
    endpoint_public_access  = false
  }
}

resource "aws_eks_node_group" "this" {
  cluster_name    = aws_eks_cluster.this.name
  node_group_name = "${var.project}-node-group"
  node_role_arn   = aws_iam_role.eks_nodes.arn
  subnet_ids      = aws_subnet.private[*].id

  scaling_config {
    desired_size = 2
    max_size     = 2
    min_size     = 1
  }

  ami_type       = "AL2023_x86_64_STANDARD"
  disk_size      = 20
  instance_types = ["t3.medium"]
}
