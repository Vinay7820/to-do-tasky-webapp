resource "kubernetes_service_account" "aws_load_balancer_controller" {
  metadata {
    name      = "aws-load-balancer-controller"
    namespace = "kube-system"
    annotations = {
      "eks.amazonaws.com/role-arn" = aws_iam_role.alb_controller.arn
    }
  }

  depends_on = [
    aws_iam_role.alb_controller,
    aws_iam_openid_connect_provider.eks,
    null_resource.update_kubeconfig
  ]

  provider = kubernetes.eks
}

