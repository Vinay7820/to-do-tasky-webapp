resource "helm_release" "aws_load_balancer_controller" {
  provider = helm
  name      = "aws-load-balancer-controller"
  repository = "https://aws.github.io/eks-charts"
  chart     = "aws-load-balancer-controller"
  namespace = "kube-system"

  set {
    name  = "clusterName"
    value = aws_eks_cluster.this.name
  }

  set {
    name  = "region"
    value = var.aws_region
  }

  set {
    name  = "vpcId"
    value = aws_vpc.this.id
  }

  set {
    name  = "serviceAccount.create"
    value = "false"
  }

  set {
    name  = "serviceAccount.name"
    value = kubernetes_service_account.alb_controller.metadata[0].name
  }

  depends_on = [
    kubernetes_service_account.alb_controller,
    aws_iam_role_policy_attachment.alb_controller,
    aws_iam_openid_connect_provider.eks,
    null_resource.update_kubeconfig
  ]
}
