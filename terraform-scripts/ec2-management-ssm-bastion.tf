###########################################
#  SSM EC2 Management Instance for EKS
###########################################

# IAM Role
resource "aws_iam_role" "eks_ssm_role" {
  name = "EKS-SSM-Role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = { Service = "ec2.amazonaws.com" }
        Action   = "sts:AssumeRole"
      }
    ]
  })
}

# Attach required policies
resource "aws_iam_role_policy_attachment" "eks_ssm_core" {
  role       = aws_iam_role.eks_ssm_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_role_policy_attachment" "eks_ssm_cluster" {
  role       = aws_iam_role.eks_ssm_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
}

resource "aws_iam_role_policy_attachment" "eks_ssm_worker" {
  role       = aws_iam_role.eks_ssm_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
}

resource "aws_iam_role_policy_attachment" "eks_ssm_ecr" {
  role       = aws_iam_role.eks_ssm_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}

# Instance Profile
resource "aws_iam_instance_profile" "eks_ssm_profile" {
  name = "EKS-SSM-Profile"
  role = aws_iam_role.eks_ssm_role.name
}

# Security Group
resource "aws_security_group" "eks_ssm_sg" {
  name        = "eks-ssm-sg"
  description = "Allow EC2 to reach EKS control plane"
  vpc_id      = aws_vpc.this.id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "eks-ssm-sg"
  }
}

# Allow EC2 to access EKS API (TCP 443)
resource "aws_security_group_rule" "allow_eks_api_ingress" {
  type                     = "ingress"
  from_port                = 443
  to_port                  = 443
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.eks_ssm_sg.id
  security_group_id        = aws_eks_cluster.this.vpc_config[0].cluster_security_group_id
}

# EC2 instance (depends on EKS cluster)
resource "aws_instance" "eks_ssm_instance" {
  ami                         = data.aws_ami.amazon_linux.id
  instance_type               = "t3.micro"
  subnet_id                   = element(aws_subnet.private[*].id, 0)
  associate_public_ip_address  = false
  iam_instance_profile         = aws_iam_instance_profile.eks_ssm_profile.name
  vpc_security_group_ids       = [aws_security_group.eks_ssm_sg.id]

  depends_on = [
    aws_eks_cluster.this,
    aws_security_group_rule.allow_eks_api_ingress
  ]

  tags = {
    Name = "EKS-SSM-Manager"
  }

  user_data = <<-EOF
    #!/bin/bash
    set -xe
    yum update -y
    yum install -y unzip curl

    # Install AWS CLI
    curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
    unzip -q awscliv2.zip
    ./aws/install

    # Install kubectl
    curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
    chmod +x kubectl
    mv kubectl /usr/local/bin/

    # Install aws-iam-authenticator
    curl -o aws-iam-authenticator https://amazon-eks.s3.us-west-2.amazonaws.com/1.29.0/2024-02-28/bin/linux/amd64/aws-iam-authenticator
    chmod +x aws-iam-authenticator
    mv aws-iam-authenticator /usr/local/bin/

    REGION=${var.aws_region}
    CLUSTER_NAME=${aws_eks_cluster.this.name}
    runuser -l ec2-user -c "aws eks update-kubeconfig --region $REGION --name $CLUSTER_NAME"
  EOF
}

# Amazon Linux 2 AMI
data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*-x86_64-gp2"]
  }
}

# Outputs
output "eks_ssm_instance_id" {
  value = aws_instance.eks_ssm_instance.id
}

output "ssm_session_command" {
  value = "aws ssm start-session --target ${aws_instance.eks_ssm_instance.id}"
}
