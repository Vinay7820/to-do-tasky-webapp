resource "aws_security_group" "mongo_sg" {
  name   = "${var.project}-mongo-sg"
  vpc_id = aws_vpc.this.id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 27017
    to_port     = 27017
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/16"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = {
    Name = "${var.project}-mongo-sg"
  }
}

data "aws_ami" "ubuntu_focal" {
  most_recent = true
  owners      = ["099720109477"] # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-focal-20.04-amd64-server-*"]
  }
}

# Step 1: Generate .pub file from your PEM (if it doesn’t already exist)
resource "null_resource" "generate_pubkey" {
  provisioner "local-exec" {
    command = "ssh-keygen -y -f ${pathexpand("~/.ssh/d-vim-mongo-server.pem")} > ${pathexpand("~/.ssh/d-vim-mongo-server.pub")}"
  }

  # This ensures we don’t regenerate unless the PEM changes
  triggers = {
    pem_hash = filesha256(pathexpand("~/.ssh/d-vim-mongo-server.pem"))
  }
}

# Step 2: Create AWS Key Pair using the generated .pub
resource "aws_key_pair" "mongo" {
  key_name   = "d-vim-mongo-server"
  public_key = file(pathexpand("~/.ssh/d-vim-mongo-server.pub"))
  depends_on = [null_resource.generate_pubkey]
}

##############################################
# MongoDB EC2 Instance with Cron Backups
##############################################

resource "random_string" "bucket_suffix" {
  length  = 6
  special = false
  upper   = false
}

resource "aws_instance" "mongo" {
  ami                    = data.aws_ami.ubuntu_focal.id
  instance_type          = "t3.micro"
  subnet_id              = aws_subnet.public[0].id
  key_name               = aws_key_pair.mongo.key_name
  vpc_security_group_ids = [aws_security_group.mongo_sg.id]
# depends_on = [
#    null_resource.disable_account_public_block
#  ]

  # Existing user_data for base setup
  user_data = templatefile("${path.module}/scripts/mongo_base.sh", {
    project       = var.project
    bucket_suffix = random_string.bucket_suffix.result
    bucket_name   = aws_s3_bucket.mongo_backups.bucket
  })
  tags = {
    Name = "${var.project}-mongo"
  }


  # Remote exec safety net
  provisioner "remote-exec" {
    inline = [
      "until systemctl status mongod >/dev/null 2>&1; do sleep 5; done",
      "until mongo --eval \"db.adminCommand('ping')\" >/dev/null 2>&1; do sleep 5; done",
      "mongo --eval 'if (db.getSiblingDB(\"taskydb\").getUser(\"taskyuser\") == null) { db.getSiblingDB(\"taskydb\").createUser({user:\"taskyuser\",pwd:\"taskypass\",roles:[{role:\"readWrite\",db:\"taskydb\"}]}) }'"
    ]

    connection {
      type        = "ssh"
      user        = "ubuntu"
      private_key = file(pathexpand("../d-vim-mongo-server.pem"))
      host        = self.public_ip
    }
  }
}

# Ensure account-level S3 Public Access Block is disabled
#resource "null_resource" "disable_account_public_block" {
#  provisioner "local-exec" {
#    command = <<EOT
#      ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
#      aws s3control put-public-access-block \
#        --account-id $ACCOUNT_ID \
#        --public-access-block-configuration '{
#          "BlockPublicAcls": false,
#          "IgnorePublicAcls": false,
#          "BlockPublicPolicy": false,
#          "RestrictPublicBuckets": false
#        }'
#    sleep 10
#    EOT
#  }
#}

resource "aws_s3_bucket" "mongo_backups" {
  bucket        = "${var.project}-mongo-backups-${random_string.bucket_suffix.result}"
  force_destroy = true
  region        = "us-east-1"
  tags = {
    Name        = "${var.project}-mongo-backups"
    Environment = "dev"
  }
#  depends_on = [null_resource.disable_account_public_block]
}

#resource "aws_s3_bucket_policy" "mongo_backups" {
# bucket = aws_s3_bucket.mongo_backups.id
#  policy = jsonencode({
#    Version = "2012-10-17",
#    Statement = [
#      {
#        Sid       = "AllowListAndGet",
#        Effect    = "Allow",
#        Principal = "*",
#        Action    = ["s3:GetObject", "s3:ListBucket"],
#        Resource = [
#          "${aws_s3_bucket.mongo_backups.arn}",
#          "${aws_s3_bucket.mongo_backups.arn}/*"
#        ]
#      }
#    ]
#  })


resource "aws_s3_bucket_policy" "mongo_backups" {
  bucket = aws_s3_bucket.mongo_backups.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect    = "Allow"
        Principal = "*"
        Action    = ["s3:GetObject", "s3:PutObject", "s3:ListBucket"]
        Resource  = "${aws_s3_bucket.mongo_backups.arn}/*"
      }
    ]
  })


  # Wait for both bucket creation *and* public block disable
  depends_on = [
    aws_s3_bucket.mongo_backups,
#    null_resource.disable_account_public_block
  ]
}
