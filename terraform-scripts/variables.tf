variable "project" {
  default = "tasky-wiz"
}

variable "aws_region" {
  default = "ap-south-1"
}

variable "ssh_key_name" {
  description = "EC2 Key Pair for Mongo VM"
}

resource "random_string" "suffix" {
  length  = 4
  upper   = false
  special = false
}

variable "manage_aws_auth" {
  description = "Whether to let Terraform manage the aws-auth ConfigMap"
  type        = bool
  default     = false
}


