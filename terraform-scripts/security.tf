# ---------------------------
# AWS Config Setup
# ---------------------------

# Create an S3 bucket for AWS Config logs
resource "aws_s3_bucket" "config_bucket" {
  bucket        = "${var.project}-config-logs-${random_string.suffix.result}"
  force_destroy = true
}

resource "random_string_local" "config_suffix" {
  length  = 6
  upper   = false
  special = false
}

resource "aws_s3_bucket" "config_logs" {
  bucket = "${var.project}-config-logs-${random_string_local.config_suffix.result}"
  force_destroy = true
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "config.amazonaws.com"
        }
        Action = "s3:*"
        Resource = [
          aws_s3_bucket.config_logs.arn,
          "${aws_s3_bucket.config_logs.arn}/*"
        ]
      }
    ]
  })
  tags = {
    Name        = "${var.project}-config-logs"
    Environment = "dev"
  }
}

resource "aws_s3_bucket_ownership_controls" "config_logs" {
  bucket = aws_s3_bucket.config_logs.id
  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}


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
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSConfigRole"
}


# AWS Config Recorder
resource "aws_config_configuration_recorder" "main" {
  name     = "${var.project}-recorder"
  role_arn = aws_iam_role.config_role.arn

  recording_group {
    all_supported = true
    include_global_resource_types = true
  }
}

# AWS Config Delivery Channel
resource "aws_config_delivery_channel" "main" {
  name           = "${var.project}-channel"
  s3_bucket_name = aws_s3_bucket.config_bucket.bucket

  depends_on = [aws_config_configuration_recorder.main]
}

# Ensure recorder is running
resource "aws_config_configuration_recorder_status" "main" {
  name       = aws_config_configuration_recorder.main.name
  is_enabled = true
}

# ---------------------------
# AWS Config Managed Rules
# ---------------------------

# Rule: No public S3 buckets
resource "aws_config_config_rule" "s3_no_public_read" {
  name = "s3-bucket-public-read-prohibited"

  source {
    owner             = "AWS"
    source_identifier = "S3_BUCKET_PUBLIC_READ_PROHIBITED"
  }
}

# Rule: No public SSH
resource "aws_config_config_rule" "ec2_no_public_ssh" {
  name = "ec2-security-group-no-public-ssh"

  source {
    owner             = "AWS"
    source_identifier = "INCOMING_SSH_DISABLED"
  }
}
