# Get the OIDC issuer for EKS
data "aws_eks_cluster" "this" {
  name = aws_eks_cluster.this.name
}

# OIDC provider for IRSA
resource "aws_iam_openid_connect_provider" "eks" {
  url = data.aws_eks_cluster.this.identity[0].oidc[0].issuer
  client_id_list = ["sts.amazonaws.com"]
}

# ALB Controller IAM Role for Service Account
resource "aws_iam_role" "alb_controller" {
  name = "tasky-wiz-alb-controller-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Federated = aws_iam_openid_connect_provider.eks.arn
      }
      Action = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "${replace(aws_iam_openid_connect_provider.eks.url, "https://", "")}:sub" = "system:serviceaccount:kube-system:aws-load-balancer-controller"
        }
      }
    }]
  })
}

# Attach AWS-managed or custom ALB policy
resource "aws_iam_policy_attachment" "alb_policy_attach" {
  name       = "alb-policy-attach"
  roles      = [aws_iam_role.alb_controller.name]
  policy_arn = "arn:aws:iam::150575195000:policy/AWSLoadBalancerControllerIAMPolicy"
}

# Kubernetes service account linked to IAM role (IRSA)
resource "kubernetes_service_account" "alb_controller" {
  provider = kubernetes.eks
  metadata {
    name      = "aws-load-balancer-controller"
    namespace = "kube-system"
    annotations = {
      "eks.amazonaws.com/role-arn" = aws_iam_role.alb_controller.arn
    }
  }

  depends_on = [
    aws_iam_openid_connect_provider.eks,
    aws_iam_role.alb_controller,
    aws_iam_policy_attachment.alb_policy_attach
  ]
}

