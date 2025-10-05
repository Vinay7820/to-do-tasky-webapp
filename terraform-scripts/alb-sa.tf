resource "kubernetes_service_account" "alb_controller" {
  provider = kubernetes.eks

  metadata {
    name      = "aws-load-balancer-controller"
    namespace = "kube-system"
    labels = {
      "app.kubernetes.io/name" = "aws-load-balancer-controller"
    }
  }

  depends_on = [
    aws_iam_role.alb_controller,
    aws_iam_openid_connect_provider.eks,
    aws_eks_cluster.this,
    aws_eks_node_group.this,
    null_resource.update_kubeconfig
  ]
}
