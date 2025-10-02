resource "aws_security_group" "mongo_sg" {
  vpc_id = aws_vpc.this.id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port       = 27017
    to_port         = 27017
    protocol        = "tcp"
    cidr_blocks     = ["10.0.0.0/16"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
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

resource "aws_instance" "mongo" {
  ami           = data.aws_ami.ubuntu_focal.id
  instance_type = "t3.micro"
  subnet_id     = aws_subnet.public[0].id
  key_name      = var.ssh_key_name
  vpc_security_group_ids = [aws_security_group.mongo_sg.id]

  user_data = <<-EOF
              #!/bin/bash
              set -xe

              # Update base packages
              apt-get update -y
              apt-get install -y gnupg curl awscli

              # Add MongoDB 5.0 repo
              curl -fsSL https://pgp.mongodb.com/server-5.0.asc | gpg --dearmor -o /usr/share/keyrings/mongodb-archive-keyring.gpg
              echo "deb [ arch=amd64,arm64 signed-by=/usr/share/keyrings/mongodb-archive-keyring.gpg ] https://repo.mongodb.org/apt/ubuntu focal/mongodb-org/5.0 multiverse" \
                | tee /etc/apt/sources.list.d/mongodb-org-5.0.list

              # Install MongoDB
              apt-get update -y
              apt-get install -y mongodb-org

              # Update mongod.conf to listen on all interfaces
              sed -i 's/^  bindIp:.*$/  bindIp: 0.0.0.0/' /etc/mongod.conf

              # Enable and start Mongo
              systemctl enable mongod
              systemctl restart mongod

              # Wait until Mongo is ready
              until mongo --eval "db.adminCommand('ping')" >/dev/null 2>&1; do
                sleep 2
              done

              # Create user inside taskydb
              mongo --eval 'use taskydb; db.createUser({user:"taskyuser",pwd:"taskypass",roles:[{role:"readWrite",db:"taskydb"}]})'

              # Setup cron backup
              echo "0 2 * * * root mongodump --out /tmp/mongobackup && aws s3 cp --recursive /tmp/mongobackup s3://${var.project}-mongo-backups/" >> /etc/crontab
              EOF
}


resource "aws_s3_bucket" "mongo_backups" {
  bucket        = "${var.project}-mongo-backups-${random_string.suffix.result}"
  force_destroy = true
}


resource "aws_s3_bucket_policy" "mongo_backups" {
  bucket = aws_s3_bucket.mongo_backups.id
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Principal = "*",
        Action   = ["s3:GetObject", "s3:ListBucket"],
        Resource = [
          "${aws_s3_bucket.mongo_backups.arn}",
          "${aws_s3_bucket.mongo_backups.arn}/*"
        ]
      }
    ]
  })
}
