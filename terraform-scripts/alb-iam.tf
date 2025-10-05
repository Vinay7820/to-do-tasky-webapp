#########################################
# ALB Controller IAM + OIDC Integration #
#########################################

# Fetch EKS cluster details
data "aws_eks_cluster" "this" {
  name = aws_eks_cluster.this.name
}

# Fetch authentication info for cluster
data "aws_eks_cluster_auth" "this" {
  name = aws_eks_cluster.this.name
}

# Create an IAM OIDC provider for EKS
resource "aws_iam_openid_connect_provider" "eks" {
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.aws_eks_cluster.this.certificate_authority[0].data]
  url             = data.aws_eks_cluster.this.identity[0].oidc[0].issuer
}

# Create IAM role for ALB controller
resource "aws_iam_role" "alb_controller" {
  name = "AWSLoadBalancerControllerRole"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Federated = aws_iam_openid_connect_provider.eks.arn
        }
        Action = "sts:AssumeRoleWithWebIdentity"
        Condition = {
          StringEquals = {
            "${replace(data.aws_eks_cluster.this.identity[0].oidc[0].issuer, "https://", "")}:sub" = "system:serviceaccount:kube-system:aws-load-balancer-controller"
          }
        }
      }
    ]
  })
}

# Create the ALB Controller IAM Policy
resource "aws_iam_policy" "alb_controller" {
  name        = "AWSLoadBalancerControllerIAMPolicy"
  description = "Policy for ALB Controller to manage AWS resources"

  policy = file("${path.module}/policies/AWSLoadBalancerControllerIAMPolicy.json")
}

# Attach the policy to the role
resource "aws_iam_role_policy_attachment" "alb_controller" {
  role       = aws_iam_role.alb_controller.name
  policy_arn = aws_iam_policy.alb_controller.arn
}
