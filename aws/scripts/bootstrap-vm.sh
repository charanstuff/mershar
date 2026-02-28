#!/usr/bin/env bash
# Bootstrap a single VM (e.g. EC2) with Docker, Kind, kubectl, Helm, and ingress-nginx.
# Run as a user that can use Docker (e.g. ec2-user after logout/login if docker group was added).
# Usage: ./bootstrap-vm.sh [kind-cluster-name]

set -euo pipefail

KIND_CLUSTER="${1:-openclaw}"

# --- Docker (if not already installed) ---
if ! command -v docker &>/dev/null; then
  echo "Installing Docker..."
  sudo dnf install -y docker 2>/dev/null || sudo yum install -y docker
  sudo systemctl enable docker
  sudo systemctl start docker
  sudo usermod -aG docker "$(whoami)" || true
  echo "Docker installed. You may need to log out and back in for group membership."
fi

# --- kubectl ---
if ! command -v kubectl &>/dev/null; then
  echo "Installing kubectl..."
  curl -sSL "https://dl.k8s.io/release/$(curl -sL https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl" -o /tmp/kubectl
  chmod +x /tmp/kubectl
  sudo mv /tmp/kubectl /usr/local/bin/kubectl
fi

# --- Kind ---
if ! command -v kind &>/dev/null; then
  echo "Installing Kind..."
  curl -sSL "https://kind.sigs.k8s.io/dl/v0.20.0/kind-linux-amd64" -o /tmp/kind
  chmod +x /tmp/kind
  sudo mv /tmp/kind /usr/local/bin/kind
fi

# --- Helm ---
if ! command -v helm &>/dev/null; then
  echo "Installing Helm..."
  curl -sSL "https://get.helm.sh/helm-v3.13.0-linux-amd64.tar.gz" | tar xz -C /tmp
  sudo mv /tmp/linux-amd64/helm /usr/local/bin/helm
fi

# --- Kind cluster ---
if ! kind get kubeconfig --name "$KIND_CLUSTER" &>/dev/null; then
  echo "Creating Kind cluster: $KIND_CLUSTER"
  kind create cluster --name "$KIND_CLUSTER"
fi

export KUBECONFIG="$HOME/.kube/config"
# Kind merges kubeconfig; ensure we use the cluster we created
kind get kubeconfig --name "$KIND_CLUSTER" > "$HOME/.kube/kind-$KIND_CLUSTER-config"
export KUBECONFIG="$HOME/.kube/kind-$KIND_CLUSTER-config"

echo "Waiting for cluster to be ready..."
kubectl wait --for=condition=Ready nodes --all --timeout=120s 2>/dev/null || true

# --- Ingress-nginx (Option A: TLS at edge) ---
# Use hostNetwork so the controller binds to host 80/443 (no NodePort needed).
if ! kubectl get deployment -n ingress-nginx ingress-nginx-controller &>/dev/null; then
  echo "Installing ingress-nginx (hostNetwork so ports 80/443 on VM)..."
  helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx 2>/dev/null || true
  helm repo update
  helm upgrade --install ingress-nginx ingress-nginx/ingress-nginx \
    --namespace ingress-nginx \
    --create-namespace \
    --set controller.hostNetwork=true \
    --set controller.service.type=ClusterIP \
    --wait --timeout 120s
else
  echo "ingress-nginx already installed."
fi

echo ""
echo "Bootstrap done. Next:"
echo "  1. Create TLS secret: kubectl create secret tls openclaw-tls --cert=fullchain.pem --key=privkey.pem -n default"
echo "  2. Deploy OpenClaw with aws/values/values-aws.yaml (see aws/README.md)"
echo "  KUBECONFIG=$KUBECONFIG"
