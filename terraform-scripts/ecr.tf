resource "aws_ecr_repository" "this" {
  name = "${var.project}-tasky"
}

resource "null_resource" "push_image" {
  depends_on = [
    aws_ecr_repository.this,
    aws_eks_cluster.this
  ]

  provisioner "local-exec" {
    command     =<<EOT
      chmod +x ./push.sh
      ./push.sh
    EOT
    working_dir = "${path.module}"   # ensures it runs from terraform-scripts/
  }
}
