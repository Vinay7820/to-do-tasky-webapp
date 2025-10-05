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

  set = {
    "clusterName"           = aws_eks_cluster.this.name
    "region"                = var.aws_region
    "vpcId"                 = aws_vpc.this.id
    "serviceAccount.create" = "false"
    "serviceAccount.name"   = "aws-load-balancer-controller"
  }

  depends_on = [
    kubernetes_service_account.alb_controller,
    aws_iam_policy_attachment.alb_policy_attach
  ]
}

