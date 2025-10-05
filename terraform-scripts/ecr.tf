resource "aws_ecr_repository" "this" {
  name = "${var.project}-tasky"
  image_scanning_configuration {
    scan_on_push = true
  }
}

resource "null_resource" "push_image" {
  depends_on = [
    aws_ecr_repository.this,
    aws_eks_cluster.this
  ]

  provisioner "local-exec" {
    command     = <<EOT
      chmod +x ${path.module}/push.sh
      ${path.module}/push.sh
      ${path.module}/push.sh wiz-v1
    EOT
    working_dir = path.module
  }
}

#resource "null_resource" "push_image" {
#  depends_on = [aws_instance.eks_management]

#  connection {
#    type   = "session"
#    target = aws_instance.eks_management.id
#  }

#  provisioner "remote-exec" {
#    inline = [
#      "echo 'Deploying app to EKS from inside VPC...'",
#      "kubectl apply -f /home/ec2-user/k8s/"
#    ]
#  }
#}

