# OIDC provider for the EKS cluster
resource "aws_iam_openid_connect_provider" "eks" {
  url             = data.aws_eks_cluster.this.identity[0].oidc[0].issuer
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = ["9e99a48a9960b14926bb7f3b02e22da0afd10b5c"]

  depends_on = [aws_eks_cluster.this]
}

