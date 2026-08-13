variable "aws_region" {
  default = "us-east-1"
}

variable "your_ip" {
  description = "Your home/office IP for SSH admin access (CIDR notation, e.g. 1.2.3.4/32)"
  type        = string
}

variable "key_name" {
  description = "Name of an existing EC2 key pair"
  type        = string
}

variable "ami_id" {
  # Ubuntu 22.04 LTS in us-east-1 — check AWS console for your region
  default = "ami-0c7217cdde317cfec"
}
