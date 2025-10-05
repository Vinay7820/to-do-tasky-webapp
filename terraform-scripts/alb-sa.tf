#######################################
# Service Account for ALB Controller  #
#######################################

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
    aws_iam_role.alb_controller,
    aws_iam_role_policy_attachment.alb_controller,
    aws_iam_openid_connect_provider.eks
  ]
}
