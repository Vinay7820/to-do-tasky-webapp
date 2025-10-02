📝 Tasky WebApp – Two-Tier Deployment on AWS EKS + MongoDB
📌 Overview

This project demonstrates a two-tier cloud-native web application (Tasky) deployed on Amazon EKS with an external MongoDB backend hosted on an EC2 instance.

It was designed intentionally with security misconfigurations for demo purposes (e.g., public MongoDB, weak IAM, hardcoded secrets).
A parallel “fixed” version shows how to secure it using best practices.

🏗️ Architecture

Frontend: Gin (Go) web app containerized and deployed on Amazon EKS

Backend: MongoDB 5.x hosted on an EC2 instance

Networking: Public ALB/NLB in front of EKS, VPC with public + private subnets

Infra-as-Code: Terraform used to provision all resources

Secrets: Kubernetes secrets (insecure demo: plaintext, fixed demo: AWS Secrets Manager)

🚀 Deployment Steps
1️⃣ Clone the repo
git clone https://github.com/Vinay7820/to-do-tasky-webapp.git
cd to-do-tasky-webapp/terraform-scripts

2️⃣ Initialize Terraform
terraform init

3️⃣ Apply
terraform apply


When prompted for ssh_key_name, enter the name of your AWS EC2 key pair.
