#########################################
# ALB Controller IAM + OIDC Integration #
#########################################
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
