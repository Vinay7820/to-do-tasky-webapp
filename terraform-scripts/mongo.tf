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

  # Existing user_data for base setup
  user_data = file("scripts/mongo_base.sh")

  # Remote exec to (re)apply DB user creation
  provisioner "remote-exec" {
    inline = [
      # Ensure mongod is running
      "sudo systemctl start mongod || true",

      "mongo --eval 'use taskydb; db.createUser({user:\"taskyuser\",pwd:\"taskypass\",roles:[{role:\"readWrite\",db:\"taskydb\"}]})' || true"
    ]

    connection {
      type        = "ssh"
      user        = "ubuntu"
      private_key = file(pathexpand("~/.ssh/d-vim-mongo-server.pem"))
      host        = self.public_ip
    }
  }
}


resource "aws_s3_bucket" "mongo_backups" {
  bucket        = "${var.project}-mongo-backups-${random_string.suffix.result}"
  force_destroy = true
  region = "us-east-1"
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
