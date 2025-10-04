resource "null_resource" "update_kubeconfig" {
  provisioner "local-exec" {
    command = "aws eks update-kubeconfig --region us-east-1 --name ${aws_eks_cluster.this.name}"
  }

  depends_on = [aws_eks_cluster.this]
}

resource "kubernetes_namespace" "tasky" {
  metadata { name = "tasky-wiz" }
  depends_on = [
	null_resource.update_kubeconfig,
    aws_eks_cluster.this,
    aws_eks_node_group.this
  ]
}

resource "kubernetes_secret" "mongo_uri" {
  metadata {
    name      = "mongo-uri-secret"
    namespace = kubernetes_namespace.tasky.metadata[0].name
  }
  data = {
	MONGODB_URI = "mongodb://taskyuser:taskypass@${aws_instance.mongo.private_ip}:27017/taskydb"
  }

  lifecycle {
		replace_triggered_by = [aws_instance.mongo]
  }

  depends_on = [
    null_resource.update_kubeconfig,
    kubernetes_namespace.tasky,
    aws_eks_cluster.this,
    aws_eks_node_group.this
  ]
}

resource "kubernetes_service_account" "tasky" {
  metadata {
    name      = "tasky-sa"
    namespace = kubernetes_namespace.tasky.metadata[0].name
  }
}

resource "kubernetes_cluster_role_binding" "tasky_admin" {
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
    kubernetes_namespace.tasky,
    aws_eks_cluster.this,
    aws_eks_node_group.this
  ]
}

resource "kubernetes_deployment" "tasky" {
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
    null_resource.update_kubeconfig,
    aws_eks_cluster.this,
    kubernetes_namespace.tasky,
    aws_eks_node_group.this
  ]
}

resource "kubernetes_service" "tasky" {
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
    null_resource.update_kubeconfig,
	aws_eks_cluster.this,
        kubernetes_namespace.tasky,
	aws_eks_node_group.this
]
}

resource "kubernetes_ingress_v1" "tasky" {
  metadata {
    name      = "tasky-ingress"
    namespace = kubernetes_namespace.tasky.metadata[0].name
    annotations = {
      "kubernetes.io/ingress.class"                      = "alb"
      "alb.ingress.kubernetes.io/scheme"                 = "internet-facing"
      "alb.ingress.kubernetes.io/target-type"            = "ip"
      "alb.ingress.kubernetes.io/listen-ports"           = "[{\"HTTP\":80}]"
      "alb.ingress.kubernetes.io/healthcheck-path"       = "/"
      "alb.ingress.kubernetes.io/success-codes"          = "200"
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
	null_resource.update_kubeconfig,
    aws_eks_cluster.this,
    kubernetes_namespace.tasky,
    aws_eks_node_group.this
  ]
}

resource "kubernetes_config_map" "aws_auth" {
  count = var.manage_aws_auth ? 1 : 0
  metadata {
    name      = "aws-auth"
    namespace = "kube-system"
  }

  data = {
    mapRoles = yamlencode([
      {
        rolearn  = aws_iam_role.eks_nodes.arn
        username = "system:node:{{EC2PrivateDNSName}}"
        groups   = [
          "system:bootstrappers",
          "system:nodes"
        ]
      }
    ])
  }

  depends_on = [
    null_resource.update_kubeconfig,
    aws_eks_cluster.this,
    kubernetes_namespace.tasky,
    aws_eks_node_group.this
  ]
}

