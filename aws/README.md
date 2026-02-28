# OpenClaw on AWS (single VM, Kind, HTTPS at edge)

Deploy OpenClaw on a single EC2 VM with Kubernetes (Kind), **Option A: TLS at the edge** — gateway and Chromium noVNC over HTTPS via a public URL.

**→ Step-by-step: [DEPLOY.md](DEPLOY.md)**

## What this folder contains

| Path | Purpose |
|------|--------|
| **terraform/** | EC2 instance, security group (22, 80, 443). Optional: user_data to install Docker + Kind. |
| **scripts/** | Bootstrap VM (Docker, Kind, kubectl, helm, ingress-nginx), deploy OpenClaw with AWS values. |
| **values/** | Helm values for public cloud: ingress enabled, TLS, OAuth `cookieSecure: true`, noVNC path. |

## Prerequisites

- AWS CLI configured (or Terraform with credentials).
- A domain (or use EC2 public DNS) and a TLS certificate (e.g. Let's Encrypt, AWS ACM).
- OAuth app (GitHub/Google) with redirect URL set to `https://<your-host>/oauth2/callback`.

## Quick overview

1. **Terraform** – Creates an EC2 and security group; open 22 (SSH), 80, 443.
2. **Bootstrap** – On the VM: install Docker, Kind, kubectl, Helm, then install [ingress-nginx](https://kubernetes.github.io/ingress-nginx/deploy/) (and optionally cert-manager) in the cluster.
3. **TLS** – Create a Kubernetes TLS secret (e.g. from Let's Encrypt or ACM) in the cluster namespace.
4. **Deploy OpenClaw** – Use `values/values-aws.yaml` (set host, TLS secret name, OAuth redirect URL and secrets). Gateway is at `https://<host>/`, noVNC at `https://<host>/vnc/` and `https://<host>/vnc/vnc.html`.

## 1. Terraform (EC2 + security group)

```bash
cd aws/terraform
terraform init
terraform plan -var="your_key_name=my-ec2-key"
terraform apply -var="your_key_name=my-ec2-key"
```

Then SSH into the VM using the output `public_ip` and the key you specified. Ports 80 and 443 must be open in the security group (and any firewall on the VM).

## 2. Bootstrap the VM (Docker, Kind, ingress-nginx)

From your laptop you can copy and run the bootstrap script, or run it manually on the VM:

```bash
# Copy script to VM
scp -i your-key.pem aws/scripts/bootstrap-vm.sh ec2-user@<public_ip>:~

# SSH and run
ssh -i your-key.pem ec2-user@<public_ip>
chmod +x bootstrap-vm.sh
./bootstrap-vm.sh
```

This installs Docker, Kind, kubectl, Helm, creates a Kind cluster, and installs the ingress-nginx controller (NodePort or host network so ports 80/443 reach the Ingress).

## 3. TLS certificate

- **Option A – cert-manager + Let's Encrypt:** Install cert-manager in the cluster and create a `Certificate` + `ClusterIssuer` for your domain. The script or docs can create the TLS secret automatically.
- **Option B – Manual secret:** Create a TLS secret from your cert and key:

  ```bash
  kubectl create secret tls openclaw-tls \
    --cert=fullchain.pem --key=privkey.pem -n default
  ```

- **Option C – AWS ACM:** If you put an ALB in front, terminate TLS on the ALB with an ACM certificate and forward HTTP to the NodePort for ingress-nginx. Then you don't need a TLS secret inside the cluster; set `ingress.tls: []` and use HTTP in-cluster (ALB handles HTTPS).

## 4. Deploy OpenClaw with AWS values

From the **mershar** repo root (so the chart path is correct):

```bash
# Set required overrides (host, TLS secret, OAuth redirect URL and secrets)
export OPENCLAW_HOST="openclaw.example.com"
export OPENCLAW_TLS_SECRET="openclaw-tls"
export GITHUB_OAUTH_CLIENT_ID="..."
export GITHUB_OAUTH_CLIENT_SECRET="..."
export COOKIE_SECRET="..."   # or leave unset to generate

helm upgrade --install openclaw ./openclaw-helm/charts/openclaw \
  -f aws/values/values-aws.yaml \
  --set ingress.hosts[0].host="$OPENCLAW_HOST" \
  --set ingress.tls[0].secretName="$OPENCLAW_TLS_SECRET" \
  --set ingress.tls[0].hosts[0]="$OPENCLAW_HOST" \
  --set gatewayOauth2Nginx.oauth2Proxy.redirectUrl="https://$OPENCLAW_HOST/oauth2/callback" \
  --set gatewayOauth2Nginx.oauth2Proxy.clientId="$GITHUB_OAUTH_CLIENT_ID" \
  --set gatewayOauth2Nginx.oauth2Proxy.clientSecret="$GITHUB_OAUTH_CLIENT_SECRET" \
  --set gatewayOauth2Nginx.oauth2Proxy.cookieSecret="$COOKIE_SECRET" \
  -n default
```

Use the kubeconfig from Kind (e.g. from bootstrap: `export KUBECONFIG=~/.kube/kind-config` or similar).

## 5. URLs

- **Gateway / Control UI:** `https://<OPENCLAW_HOST>/`
- **Chromium noVNC:** `https://<OPENCLAW_HOST>/vnc/` and `https://<OPENCLAW_HOST>/vnc/vnc.html` (password from `chromium.vncPassword`, default `openclaw-vnc`)

## Files reference

- **terraform/** – See `terraform/README.md` for variables and outputs.
- **scripts/bootstrap-vm.sh** – Installs Docker, Kind, kubectl, Helm; creates cluster; installs ingress-nginx.
- **scripts/deploy-openclaw.sh** – Example wrapper for `helm upgrade --install` with `values/values-aws.yaml` and env-based overrides.
- **values/values-aws.yaml** – Ingress enabled, TLS and OAuth placeholders, `chromium.visibleMode: true`, gateway + noVNC paths.
