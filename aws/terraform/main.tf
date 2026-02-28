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

data "aws_ami" "amazon_linux_2023" {
  most_recent = true
  owners      = ["amazon"]
  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"]
  }
}

resource "aws_security_group" "openclaw" {
  name_prefix = "${var.name_prefix}-"
  description = "OpenClaw VM: SSH, HTTP, HTTPS"

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.allowed_cidr]
    description = "SSH"
  }

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = [var.allowed_cidr]
    description = "HTTP (redirect or Ingress)"
  }

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [var.allowed_cidr]
    description = "HTTPS (Ingress TLS)"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "All outbound"
  }
}

resource "aws_instance" "openclaw" {
  ami                    = data.aws_ami.amazon_linux_2023.id
  instance_type          = var.instance_type
  key_name               = var.your_key_name
  vpc_security_group_ids = [aws_security_group.openclaw.id]

  root_block_device {
    volume_size = 40
    volume_type = "gp3"
  }

  user_data = <<-EOT
    #!/bin/bash
    set -e
    # Minimal bootstrap: Docker only. Run aws/scripts/bootstrap-vm.sh over SSH for Kind + ingress-nginx.
    dnf update -y
    dnf install -y docker
    systemctl enable docker
    systemctl start docker
    usermod -aG docker ec2-user
    EOT

  tags = {
    Name = "${var.name_prefix}-vm"
  }
}
