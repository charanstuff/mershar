# Deploy OpenClaw to AWS (step-by-step)

This guide walks through deploying OpenClaw on a single EC2 VM with Kind, ingress-nginx, and **Option A: TLS at the edge** — gateway and Chromium noVNC over HTTPS via a public URL.

---

## Is this all that’s required?

Yes. After Terraform (VM + ports 22/80/443), bootstrap (Docker, Kind, ingress-nginx), creating a TLS secret, and running the deploy script with the right env vars, you can reach:

- **Gateway:** `https://<your-host>/`
- **noVNC:** `https://<your-host>/vnc/`

**Access by VM IP:** You can use the VM’s **public IP** (or the EC2 public DNS hostname) as the host. Set `OPENCLAW_HOST` to that IP or hostname (e.g. `3.80.1.2` or `ec2-3-80-1-2.compute-1.amazonaws.com`). You get HTTPS as long as you create a TLS secret (see below). For a bare IP, use a **self-signed certificate** — public CAs (e.g. Let’s Encrypt) do not issue certs for raw IPs. The browser will show a security warning; you accept it once to proceed.

**HTTPS:** You always need to create a **TLS secret** in the cluster (step 3). Without it, the Ingress has no cert and HTTPS won’t work. Use a real cert if you have a domain; use a self-signed cert if you’re using the VM IP or EC2 DNS only.

**HTTP disabled?** Port 80 remains open so the Ingress can accept connections, but the AWS values set **HTTP → HTTPS redirect** (`ssl-redirect: "true"`). Any request to `http://<your-host>/` is redirected to `https://<your-host>/`, so the app is only served over HTTPS. Plain HTTP is not used to serve the app.

---

## Prerequisites

- **AWS CLI** configured (or Terraform with AWS credentials)
- **EC2 key pair** in your target region (EC2 → Key Pairs in the AWS console)
- **Domain** (optional): a real domain or the EC2 public DNS; if you use only the VM IP, you’ll use a self-signed cert (see step 3).
- **TLS certificate** for that host (Let’s Encrypt for a domain, or a self-signed cert for IP/EC2 DNS).
- **OAuth app** (GitHub or Google) with redirect URL: `https://<your-host>/oauth2/callback` (use your domain or `https://<VM_IP>/oauth2/callback` if using IP).

---

## 1. Create the VM (Terraform)

From the **mershar** repo root:

```bash
cd aws/terraform
terraform init
terraform apply -var="your_key_name=YOUR_EC2_KEY_NAME"
```

When prompted, type `yes`. Note the **`public_ip`** in the output — you'll use it as `<PUBLIC_IP>` below (or point your domain at it).

---

## 2. SSH in and bootstrap the VM

Copy the bootstrap script to the EC2 instance and run it (use your key path and the IP from Terraform):

```bash
# From mershar repo root
scp -i /path/to/your-key.pem aws/scripts/bootstrap-vm.sh ec2-user@<PUBLIC_IP>:~

ssh -i /path/to/your-key.pem ec2-user@<PUBLIC_IP>
chmod +x bootstrap-vm.sh
./bootstrap-vm.sh
```

This installs Docker, Kind, kubectl, Helm, creates a Kind cluster, and installs **ingress-nginx** with hostNetwork so ports 80/443 on the VM serve the Ingress.

If Docker was just installed and your user was added to the `docker` group, log out and back in (or run `newgrp docker`) so Docker works without sudo.

---

## 3. TLS certificate (pick one)

You need a Kubernetes TLS secret named `openclaw-tls` in the `default` namespace (or set `OPENCLAW_TLS_SECRET` to another name and use it in step 6).

### Option A: Real certificate (e.g. Let's Encrypt)

On your laptop (or wherever you have the cert), create the secret. You'll need `kubectl` pointing at the cluster (see step 4):

```bash
kubectl create secret tls openclaw-tls \
  --cert=fullchain.pem \
  --key=privkey.pem \
  -n default
```

### Option B: Self-signed (required when using VM IP or EC2 DNS only)

Public CAs don’t issue certificates for bare IPs. Use a self-signed cert so the Ingress can still serve HTTPS. Browsers will show a warning; you must accept/trust the cert once to continue.

On the VM (after SSH), with `KUBECONFIG` set (e.g. `export KUBECONFIG=~/.kube/kind-openclaw-config`), create the cert with **the same host you’ll use in the browser** (VM IP or EC2 public DNS):

**If using VM IP (e.g. `3.80.1.2`):**
```bash
openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
  -keyout tls.key -out tls.crt -subj "/CN=3.80.1.2" \
  -addext "subjectAltName=IP:3.80.1.2"
kubectl create secret tls openclaw-tls --cert=tls.crt --key=tls.key -n default
```

**If using EC2 public DNS (e.g. `ec2-3-80-1-2.compute-1.amazonaws.com`):**
```bash
openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
  -keyout tls.key -out tls.crt -subj "/CN=ec2-3-80-1-2.compute-1.amazonaws.com" \
  -addext "subjectAltName=DNS:ec2-3-80-1-2.compute-1.amazonaws.com"
kubectl create secret tls openclaw-tls --cert=tls.crt --key=tls.key -n default
```

Then set `OPENCLAW_HOST` to that same IP or hostname when you deploy (step 5). In your OAuth app, set the redirect URL to `https://<that-same-host>/oauth2/callback`.

---

## 4. Point kubectl at the cluster

You need to run Helm from a machine that can reach the Kind API on the VM.

### Option A: Run everything from the VM (simplest)

Stay in the SSH session (or SSH again). The bootstrap script sets `KUBECONFIG`; ensure it's set:

```bash
export KUBECONFIG=~/.kube/kind-openclaw-config
kubectl get nodes
```

Then run the deploy step (step 6) **from the VM**. You'll need the mershar repo (and `aws/`, `openclaw-helm/`) on the VM — clone it or copy the chart and `aws/values`, `aws/scripts` over.

### Option B: Run Helm from your laptop

Copy the kubeconfig from the VM:

```bash
scp -i /path/to/your-key.pem ec2-user@<PUBLIC_IP>:~/.kube/kind-openclaw-config ~/.kube/
```

Edit the copied file and replace `127.0.0.1` in `server: https://127.0.0.1:xxxxx` with `<PUBLIC_IP>` so your laptop talks to the Kind API on the VM. Then:

```bash
export KUBECONFIG=~/.kube/kind-openclaw-config
kubectl get nodes
```

Run the deploy (step 6) from your laptop from the **mershar** repo root.

---

## 5. Set environment variables

Choose a host: your **domain**, the **EC2 public DNS** (e.g. `ec2-3-80-xxx-xxx.compute-1.amazonaws.com`), or the **VM public IP** (e.g. `3.80.1.2`). It must match the host you used in the TLS cert and the host you’ll type in the browser. Set:

```bash
export OPENCLAW_HOST="openclaw.example.com"   # or ec2-xx-xx-xx-xx.compute.amazonaws.com
export OPENCLAW_TLS_SECRET="openclaw-tls"
export GITHUB_OAUTH_CLIENT_ID="your-github-client-id"
export GITHUB_OAUTH_CLIENT_SECRET="your-github-client-secret"
```

Optional: set a cookie secret (otherwise the chart can generate one):

```bash
export COOKIE_SECRET="$(openssl rand -base64 32)"
```

For **Google OAuth** instead of GitHub, set `GOOGLE_OAUTH_CLIENT_ID` and `GOOGLE_OAUTH_CLIENT_SECRET` and use a values file that sets `provider: google` (or override in the deploy script).

---

## 6. Deploy OpenClaw

From the **mershar** repo root (on the VM if using Option A in step 4, or on your laptop if using Option B):

```bash
./aws/scripts/deploy-openclaw.sh
```

The script runs `helm upgrade --install` with `aws/values/values-aws.yaml` and the env-based overrides (host, TLS secret, OAuth, cookieSecure).

---

## 7. Access the app

- **Gateway / Control UI:** `https://<OPENCLAW_HOST>/`
- **Chromium noVNC:** `https://<OPENCLAW_HOST>/vnc/` and `https://<OPENCLAW_HOST>/vnc/vnc.html`  
  Default noVNC password: `openclaw-vnc` (set via `chromium.vncPassword` in values).

Use the same value you set for `OPENCLAW_HOST`: e.g. `https://3.80.1.2/` if you used the VM IP, or `https://your-domain/` if you used a domain (with DNS A record pointing to the VM’s public IP). If the cert is self-signed, the browser will show a warning — accept it to continue.

---

## Quick checklist

| Step | Action |
|------|--------|
| 1 | `cd aws/terraform && terraform apply -var="your_key_name=..."` |
| 2 | `scp` bootstrap script to EC2, SSH in, run `./bootstrap-vm.sh` |
| 3 | Create TLS secret `openclaw-tls` in `default` namespace |
| 4 | Set `KUBECONFIG` (on VM or laptop with edited kubeconfig) |
| 5 | Set `OPENCLAW_HOST`, `OPENCLAW_TLS_SECRET`, OAuth env vars |
| 6 | From mershar root: `./aws/scripts/deploy-openclaw.sh` |
| 7 | Open `https://<OPENCLAW_HOST>/` and `https://<OPENCLAW_HOST>/vnc/` |

---

## Troubleshooting

- **502 / connection refused:** Ingress-nginx may not be ready or hostNetwork may not be binding. Check `kubectl get pods -n ingress-nginx` and that nothing else is using 80/443 on the VM.
- **TLS warning:** For self-signed certs, accept the browser exception. For Let's Encrypt, ensure the secret exists in the same namespace as the Ingress and the host matches.
- **OAuth redirect mismatch:** The redirect URL in your IdP (GitHub/Google) must be exactly `https://<OPENCLAW_HOST>/oauth2/callback` (no trailing slash, correct host).
- **No kubeconfig on VM:** Run `export KUBECONFIG=~/.kube/kind-openclaw-config` (or the path printed by `bootstrap-vm.sh`).
