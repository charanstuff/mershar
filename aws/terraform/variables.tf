variable "aws_region" {
  description = "AWS region for EC2 and related resources"
  type        = string
  default     = "us-east-1"
}

variable "your_key_name" {
  description = "Name of the EC2 key pair for SSH access"
  type        = string
}

variable "instance_type" {
  description = "EC2 instance type for the OpenClaw VM (Kind + workloads)"
  type        = string
  default     = "t3.medium"
}

variable "allowed_cidr" {
  description = "CIDR allowed to access SSH (22), HTTP (80), HTTPS (443). Use 0.0.0.0/0 for any IP (less secure)."
  type        = string
  default     = "0.0.0.0/0"
}

variable "name_prefix" {
  description = "Prefix for resource names"
  type        = string
  default     = "openclaw"
}
