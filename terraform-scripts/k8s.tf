# This ensures all Kubernetes operations start only after cluster is reachable
locals {
  eks_ready_dependencies = [
    aws_eks_cluster.this,
    aws_eks_node_group.this,
    null_resource.wait_for_eks,
    null_resource.update_kubeconfig,
    data.external.eks_creds
  ]
}

resource "null_resource" "wait_for_nodes" {
  depends_on = [
    aws_eks_cluster.this,
    aws_eks_node_group.this,
    null_resource.wait_for_eks,
    null_resource.update_kubeconfig,
    data.external.eks_creds
  ]
  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    command     = <<EOT
CA_FILE=$(mktemp)
# write base64 CA returned by external data into a temp file
echo "${data.external.eks_creds.result["ca"]}" | base64 --decode > "$CA_FILE"

API_SERVER="${data.external.eks_creds.result["endpoint"]}"
TOKEN="${data.external.eks_creds.result["token"]}"

echo "Waiting for worker nodes to register with API server $API_SERVER..."

for i in {1..30}; do
  COUNT=$(kubectl --server="$API_SERVER" --token="$TOKEN" --certificate-authority="$CA_FILE" get nodes --no-headers 2>/dev/null | wc -l || echo 0)
  if [ "$COUNT" -gt 0 ]; then
    echo "✅ Nodes registered: $COUNT"
    rm -f "$CA_FILE"
    exit 0
  fi
  echo "No nodes yet (attempt $i/30). Sleeping 20s..."
  sleep 20
done

echo "❌ Timeout waiting for nodes to join the cluster."
rm -f "$CA_FILE"
exit 1
EOT
  }
}


#resource "null_resource" "wait_for_nodes" {
#  depends_on = [aws_instance.eks_management]

#  connection {
#    type        = "session"
#    target      = aws_instance.eks_management.id
#  }

#  provisioner "remote-exec" {
#    inline = [
#      "echo '✅ Connected via SSM to management instance...'",
#      "echo 'Waiting for EKS nodes to join...'",
#      "for i in {1..30}; do
#          COUNT=$(kubectl get nodes --no-headers 2>/dev/null | wc -l || echo 0)
#          if [ \"$COUNT\" -gt 0 ]; then
#            echo \"✅ Nodes registered: $COUNT\"
#            exit 0
#          fi
#          echo \"No nodes yet (attempt $i/30). Sleeping 20s...\"
#          sleep 20
#        done
#        echo \"❌ Timeout waiting for nodes to join the cluster.\"
#        exit 1"
#    ]
#  }
#}


resource "kubernetes_namespace" "tasky" {
  provider = kubernetes.eks
  metadata { name = "tasky-wiz" }

  depends_on = [
    aws_eks_cluster.this,
    aws_eks_node_group.this,
    null_resource.wait_for_eks,
    null_resource.update_kubeconfig,
    data.external.eks_creds
  ]
}

resource "kubernetes_secret" "mongo_uri" {
  provider = kubernetes.eks
  metadata {
    name      = "mongo-uri-secret"
    namespace = kubernetes_namespace.tasky.metadata[0].name
  }
  data = {
    # MONGODB_URI = "mongodb://taskyuser:taskypass@${aws_instance.mongo.private_ip}:27017/taskydb"
    MONGODB_URI = "mongodb://taskyuser:taskypass@${aws_instance.mongo.private_ip}:27017/go-mongodb?authSource=go-mongodb"
  }

  lifecycle {
    replace_triggered_by = [aws_instance.mongo]
  }
  depends_on = [
    aws_eks_cluster.this,
    aws_eks_node_group.this,
    null_resource.wait_for_eks,
    null_resource.update_kubeconfig,
    data.external.eks_creds
  ]
}

resource "kubernetes_service_account" "tasky" {
  provider = kubernetes.eks
  metadata {
    name      = "tasky-sa"
    namespace = kubernetes_namespace.tasky.metadata[0].name
  }
}

resource "kubernetes_cluster_role_binding" "tasky_admin" {
  provider = kubernetes.eks
  metadata { name = "tasky-admin-binding" }
  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = "cluster-admin"
  }
  subject {
    kind      = "ServiceAccount"
    name      = kubernetes_service_account.tasky.metadata[0].name
    namespace = kubernetes_namespace.tasky.metadata[0].name
  }
  depends_on = [
    aws_eks_cluster.this,
    aws_eks_node_group.this,
    null_resource.wait_for_eks,
    null_resource.update_kubeconfig,
    data.external.eks_creds
  ]
}

resource "kubernetes_deployment" "tasky" {
  provider = kubernetes.eks
  metadata {
    name      = "tasky"
    namespace = kubernetes_namespace.tasky.metadata[0].name
    labels = {
      app = "tasky"
    }
  }

  spec {
    replicas = 2
    selector { match_labels = { app = "tasky" } }

    template {
      metadata { labels = { app = "tasky" } }
      spec {
        service_account_name = kubernetes_service_account.tasky.metadata[0].name
        container {
          name  = "tasky"
          image = "${aws_ecr_repository.this.repository_url}:wiz-v1"
          port { container_port = 8080 }
          env {
            name = "MONGODB_URI"
            value_from {
              secret_key_ref {
                name = kubernetes_secret.mongo_uri.metadata[0].name
                key  = "MONGODB_URI"
              }
            }
          }

        }
      }
    }
  }
  depends_on = [
    aws_eks_cluster.this,
    aws_eks_node_group.this,
    null_resource.wait_for_eks,
    null_resource.update_kubeconfig,
    data.external.eks_creds
  ]
}

resource "kubernetes_service" "tasky" {
  provider = kubernetes.eks
  metadata {
    name      = "tasky-service"
    namespace = kubernetes_namespace.tasky.metadata[0].name
    labels = {
      app = "tasky"
    }
  }

  spec {
    selector = {
      app = kubernetes_deployment.tasky.spec[0].selector[0].match_labels.app
    }

    type = "NodePort"
    port {
      port        = 80
      target_port = 8080
      protocol    = "TCP"
    }
  }
  depends_on = [
    aws_eks_cluster.this,
    aws_eks_node_group.this,
    null_resource.wait_for_eks,
    null_resource.update_kubeconfig,
    data.external.eks_creds
  ]
}

resource "kubernetes_ingress_v1" "tasky" {
  provider = kubernetes.eks
  metadata {
    name      = "tasky-ingress"
    namespace = kubernetes_namespace.tasky.metadata[0].name
    annotations = {
      "kubernetes.io/ingress.class"                = "alb"
      "alb.ingress.kubernetes.io/scheme"           = "internet-facing"
      "alb.ingress.kubernetes.io/target-type"      = "ip"
      "alb.ingress.kubernetes.io/listen-ports"     = "[{\"HTTP\":80}]"
      "alb.ingress.kubernetes.io/healthcheck-path" = "/"
      "alb.ingress.kubernetes.io/success-codes"    = "200"
    }
  }
  spec {
    ingress_class_name = "alb"
    rule {
      http {
        path {
          path      = "/"
          path_type = "Prefix"
          backend {
            service {
              name = kubernetes_service.tasky.metadata[0].name
              port { number = 80 }
            }
          }
        }
      }
    }
  }
  depends_on = [
    aws_eks_cluster.this,
    aws_eks_node_group.this,
    null_resource.wait_for_eks,
    null_resource.update_kubeconfig,
    data.external.eks_creds
  ]
}

resource "kubernetes_config_map" "aws_auth" {
  provider = kubernetes.eks
  count    = var.manage_aws_auth ? 1 : 0
  metadata {
    name      = "aws-auth"
    namespace = "kube-system"
  }

  data = {
    mapRoles = yamlencode([
      {
        rolearn  = aws_iam_role.eks_nodes.arn
        username = "system:node:{{EC2PrivateDNSName}}"
        groups = [
          "system:bootstrappers",
          "system:nodes"
        ]
      }
    ])
  }
  depends_on = [
    aws_eks_cluster.this,
    aws_eks_node_group.this,
    null_resource.wait_for_eks,
    null_resource.update_kubeconfig,
    data.external.eks_creds
  ]
}

