terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

# ─── Networking ───────────────────────────────────────────────────────────────

resource "aws_vpc" "honeypot" {
  cidr_block           = "10.10.0.0/16"
  enable_dns_hostnames = true
  tags = { Name = "honeypot-vpc" }
}

resource "aws_internet_gateway" "honeypot" {
  vpc_id = aws_vpc.honeypot.id
  tags   = { Name = "honeypot-igw" }
}

resource "aws_subnet" "honeypot_public" {
  vpc_id                  = aws_vpc.honeypot.id
  cidr_block              = "10.10.1.0/24"
  map_public_ip_on_launch = true
  availability_zone       = "${var.aws_region}a"
  tags                    = { Name = "honeypot-public-subnet" }
}

resource "aws_route_table" "honeypot" {
  vpc_id = aws_vpc.honeypot.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.honeypot.id
  }
  tags = { Name = "honeypot-rt" }
}

resource "aws_route_table_association" "honeypot" {
  subnet_id      = aws_subnet.honeypot_public.id
  route_table_id = aws_route_table.honeypot.id
}

# ─── Security Group ──────────────────────────────────────────────────────────

resource "aws_security_group" "honeypot" {
  name   = "honeypot-sg"
  vpc_id = aws_vpc.honeypot.id

  # Admin SSH — only from YOUR IP
  ingress {
    description = "Admin SSH from operator"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.your_ip]
  }

  # Cowrie listens on 2222 — open to internet to attract attackers
  ingress {
    description = "Honeypot SSH (Cowrie)"
    from_port   = 2222
    to_port     = 2222
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Cowrie Telnet honeypot (optional)
  ingress {
    description = "Honeypot Telnet (Cowrie)"
    from_port   = 23
    to_port     = 23
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "honeypot-sg" }
}

# ─── IAM Role for CloudWatch ──────────────────────────────────────────────────

resource "aws_iam_role" "honeypot_role" {
  name = "honeypot_cloudwatch_role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "cloudwatch_agent_policy" {
  role       = aws_iam_role.honeypot_role.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
}

resource "aws_iam_instance_profile" "honeypot_profile" {
  name = "honeypot_instance_profile"
  role = aws_iam_role.honeypot_role.name
}

# ─── CloudWatch Log Group ─────────────────────────────────────────────────────

resource "aws_cloudwatch_log_group" "cowrie_logs" {
  name              = "/honeypot/cowrie"
  retention_in_days = 30
}

# ─── EC2 Instance ─────────────────────────────────────────────────────────────

resource "aws_instance" "honeypot" {
  ami                    = var.ami_id
  instance_type          = "t3.micro"
  subnet_id              = aws_subnet.honeypot_public.id
  vpc_security_group_ids = [aws_security_group.honeypot.id]
  key_name               = var.key_name
  iam_instance_profile   = aws_iam_instance_profile.honeypot_profile.name

  root_block_device {
    volume_size = 20
    volume_type = "gp3"
  }

  tags = { Name = "cowrie-honeypot" }
}
