# ---------------------------
# AWS Config Detective Control (No Public SSH)
# ---------------------------

# IAM Role for AWS Config
resource "aws_iam_role" "config_role" {
  name = "${var.project}-config-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Action = "sts:AssumeRole",
      Effect = "Allow",
      Principal = {
        Service = "config.amazonaws.com"
      }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "config_role_attach" {
  role       = aws_iam_role.config_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSConfigRulesExecutionRole"
}

# AWS Config Managed Rule: No Public SSH
resource "aws_config_config_rule" "ec2_no_public_ssh" {
  name = "ec2-security-group-no-public-ssh"

  source {
    owner             = "AWS"
    source_identifier = "INCOMING_SSH_DISABLED"
  }
}
