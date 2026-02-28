# Terraform: EC2 + security group for OpenClaw

Creates a single EC2 instance (Amazon Linux 2023) and a security group allowing:

- **22** – SSH
- **80** – HTTP (for Ingress or redirect to HTTPS)
- **443** – HTTPS (TLS at Ingress)

## Usage

```bash
terraform init
terraform plan   -var="your_key_name=my-ec2-key"
terraform apply  -var="your_key_name=my-ec2-key"
```

## Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `your_key_name` | EC2 key pair name (required) | — |
| `aws_region` | AWS region | `us-east-1` |
| `instance_type` | EC2 type | `t3.medium` |
| `allowed_cidr` | CIDR for ingress rules | `0.0.0.0/0` |
| `name_prefix` | Resource name prefix | `openclaw` |

## Outputs

- `public_ip` – Use for SSH and for DNS (or point your domain here).
- `ssh_command` – Example `ssh ...` command.

## After apply

1. SSH into the VM and run `aws/scripts/bootstrap-vm.sh` (or copy the script and run it) to install Docker, Kind, kubectl, Helm, and ingress-nginx.
2. Create a TLS secret (or use cert-manager) and deploy OpenClaw with `aws/values/values-aws.yaml` as in the main [aws/README.md](../README.md).
