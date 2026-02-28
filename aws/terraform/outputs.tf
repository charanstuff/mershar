output "public_ip" {
  description = "Public IP of the OpenClaw EC2 instance"
  value       = aws_instance.openclaw.public_ip
}

output "security_group_id" {
  description = "Security group ID attached to the instance"
  value       = aws_security_group.openclaw.id
}

output "ssh_command" {
  description = "Example SSH command (replace key path and ensure key has correct permissions)"
  value       = "ssh -i /path/to/your-key.pem ec2-user@${aws_instance.openclaw.public_ip}"
}
