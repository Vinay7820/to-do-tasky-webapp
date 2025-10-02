resource "aws_ecr_repository" "this" {
  name = "${var.project}-tasky"
}
