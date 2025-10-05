provider "helm" {
  kubernetes = {
    host                   = data.external.eks_creds.result["endpoint"]
    cluster_ca_certificate = base64decode(data.external.eks_creds.result["ca"])
    token                  = data.external.eks_creds.result["token"]
  }
}

resource "helm_release" "aws_load_balancer_controller" {
  name       = "aws-load-balancer-controller"
  repository = "https://aws.github.io/eks-charts"
  chart      = "aws-load-balancer-controller"
  namespace  = "kube-system"
  version    = "1.13.4"

  depends_on = [
    kubernetes_service_account.alb_controller,
    aws_iam_role.alb_controller
  ]

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
    value = "aws-load-balancer-controller"
  }

  depends_on = [
    kubernetes_service_account.alb_controller,
    aws_iam_policy_attachment.alb_policy_attach
  ]
}

