resource "aws_ecr_repository" "this" {
  name = "${var.project}-tasky"
}

resource "null_resource" "push_image" {
  depends_on = [
    aws_ecr_repository.this,
    aws_eks_cluster.this
  ]

 provisioner "local-exec" {
    command = <<EOT
      chmod +x ${path.module}/push.sh
      ${path.module}/push.sh
      ${path.module}/push.sh wiz-v1
    EOT
    working_dir = "${path.module}"
  }
}
