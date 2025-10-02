output "eks_cluster_name" {
  description = "EKS cluster name"
  value       = aws_eks_cluster.this.name
}

output "eks_cluster_endpoint" {
  description = "EKS cluster endpoint"
  value       = aws_eks_cluster.this.endpoint
}

output "eks_node_group_name" {
  description = "EKS node group name"
  value       = aws_eks_node_group.this.node_group_name
}

output "eks_nodes_role_arn" {
  description = "IAM role ARN for worker nodes"
  value       = aws_iam_role.eks_nodes.arn
}

output "eks_update_kubeconfig_command" {
  description = "Run this command to update your kubeconfig and connect kubectl to your EKS cluster"
  value       = "aws eks update-kubeconfig --region ${var.aws_region} --name ${aws_eks_cluster.this.name}"
}

output "push_image_command" {
  description = "Run this command to build and push your Docker image"
  value       = <<EOT
REGION=${var.region}
REPO_URI=$(terraform -chdir=terraform-scripts output -raw ecr_repo_uri)
./push.sh
EOT
}



