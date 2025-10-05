#########################################
# ALB Controller IAM + OIDC Integration #
#########################################
# --- Create IAM OIDC provider for EKS ---
resource "aws_iam_openid_connect_provider" "eks" {
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = ["9e99a48a9960b14926bb7f3b02e22da0afd10af5"] # standard AWS OIDC thumbprint
  url             = data.aws_eks_cluster.this.identity[0].oidc[0].issuer
}

# --- IAM Role for ALB Controller ---
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

# --- Create ALB Controller IAM Policy ---
resource "aws_iam_policy" "alb_controller" {
  name        = "AWSLoadBalancerControllerIAMPolicy"
  description = "Policy for AWS Load Balancer Controller"

  policy = file("${path.module}/policies/aws-load-balancer-controller-policy.json")
}

# --- Attach Policy to Role ---
resource "aws_iam_role_policy_attachment" "alb_controller" {
  role       = aws_iam_role.alb_controller.name
  policy_arn = aws_iam_policy.alb_controller.arn
}
