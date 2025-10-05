# AWS provider
provider "aws" {
  region = var.aws_region
}

data "aws_eks_cluster" "this" {
  name = aws_eks_cluster.this.name
}

data "aws_eks_cluster_auth" "this" {
  name = aws_eks_cluster.this.name
}


# --- Wait for EKS to be Active ---
resource "null_resource" "wait_for_eks" {
  depends_on = [aws_eks_cluster.this]

  provisioner "local-exec" {
    command = <<EOT
      echo "Waiting for EKS cluster to become ACTIVE..."
      for i in {1..30}; do
        STATUS=$(aws eks describe-cluster --name ${aws_eks_cluster.this.name} --region ${var.aws_region} --query "cluster.status" --output text)
        if [ "$STATUS" = "ACTIVE" ]; then
          echo "✅ EKS cluster is ACTIVE!"
          exit 0
        fi
        echo "Still $STATUS... waiting 20s"
        sleep 20
      done
      echo "❌ EKS did not become ACTIVE in time."
      exit 1
    EOT
  }
}

# --- Update kubeconfig once EKS is ready ---
resource "null_resource" "update_kubeconfig" {
  depends_on = [null_resource.wait_for_eks]

  provisioner "local-exec" {
    command = "aws eks update-kubeconfig --region ${var.aws_region} --name ${aws_eks_cluster.this.name}"
  }
}

# --- Fetch EKS connection details (AFTER cluster is ready) ---
data "external" "eks_creds" {
  program = [
    "bash",
    "${path.module}/scripts/eks-get-credentials.sh",
    aws_eks_cluster.this.name,
    var.aws_region,
    "600"
  ]

  depends_on = [
    aws_eks_cluster.this,
    null_resource.wait_for_eks,
    null_resource.update_kubeconfig,
    aws_eks_node_group.this
  ]
}

# --- Define Kubernetes provider with alias ---
provider "kubernetes" {
  alias                  = "eks"
  host                   = data.external.eks_creds.result["endpoint"]
  cluster_ca_certificate = base64decode(data.external.eks_creds.result["ca"])
  token                  = data.external.eks_creds.result["token"]

  #avoid reading any local kubeconfig
  #load_config_file = false
}

provider "helm" {
  kubernetes = {
    host                   = data.external.eks_creds.result["endpoint"]
    cluster_ca_certificate = base64decode(data.external.eks_creds.result["ca"])
    token                  = data.external.eks_creds.result["token"]
  }
}


