# ---------------------------
# AWS Config Setup (Detective Control Only)
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

# Attach the correct AWS-managed policy for Config rules
resource "aws_iam_role_policy_attachment" "config_role_attach" {
  role       = aws_iam_role.config_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSConfigRulesExecutionRole"
}

# AWS Config Recorder (records resource changes)
resource "aws_config_configuration_recorder" "main" {
  name     = "${var.project}-recorder"
  role_arn = aws_iam_role.config_role.arn

  recording_group {
    all_supported             = true
    include_global_resource_types = true
  }
}

# AWS Config Delivery Channel (required, but no bucket needed if using default)
resource "aws_config_delivery_channel" "main" {
  name = "${var.project}-channel"
  # No S3 bucket configured (relies on AWS Config service defaults)
  depends_on = [aws_config_configuration_recorder.main]
}

# Ensure recorder is running
resource "aws_config_configuration_recorder_status" "main" {
  name       = aws_config_configuration_recorder.main.name
  is_enabled = true
  depends_on = [aws_config_delivery_channel.main]
}

# ---------------------------
# AWS Config Managed Rules
# ---------------------------

# Rule: No public SSH access allowed (detective control)
resource "aws_config_config_rule" "ec2_no_public_ssh" {
  name = "ec2-security-group-no-public-ssh"

  source {
    owner             = "AWS"
    source_identifier = "INCOMING_SSH_DISABLED"
  }
}
