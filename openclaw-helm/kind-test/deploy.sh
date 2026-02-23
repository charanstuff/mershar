#!/usr/bin/env bash
# Deploy a Kind cluster with multiple nodes and install OpenClaw via the Helm chart.
# Prerequisites: Docker running, kubectl and helm on PATH. Optionally kind on PATH
# or a kind binary at kind-test/kind (script will use it if present).
#
# Usage:
#   ./kind-test/deploy.sh [cluster-name]
#
# Optional env:
#   ANTHROPIC_API_KEY       - Anthropic API key (default: placeholder)
#   OPENAI_API_KEY          - OpenAI API key (use this instead of Anthropic for OpenAI models)
#   OPENAI_PROJECT_ID       - OpenAI project ID (required for sk-proj- keys, e.g. Default project)
#   OPENAI_ORG_ID           - OpenAI organization ID (optional, for multi-org)
#   OPENCLAW_NAMESPACE      - Kubernetes namespace (default: default)
#   OPENCLAW_BUILD_LOCAL    - If set to 1, build OpenClaw image from ../openclaw and load into Kind (use local image with header-auth)
#   GOOGLE_OAUTH_CLIENT_ID  - If set, use values-google-oauth.yaml (oauth2-proxy + nginx, @gmail.com only)
#   GOOGLE_OAUTH_CLIENT_SECRET - Required when GOOGLE_OAUTH_CLIENT_ID is set
#   COOKIE_SECRET           - Optional; auto-generated if unset and using Google OAuth
#
# Kubeconfig is written to kind-test/kubeconfig (relative to repo root).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
CLUSTER_NAME="${1:-openclaw}"
KIND_CONFIG="$SCRIPT_DIR/kind-config.yaml"
KUBECONFIG_PATH="$SCRIPT_DIR/kubeconfig"
NAMESPACE="${OPENCLAW_NAMESPACE:-default}"
ANTHROPIC_KEY="${ANTHROPIC_API_KEY:-sk-ant-test-placeholder}"
OPENAI_KEY="${OPENAI_API_KEY:-}"
OPENAI_PROJECT_ID="${OPENAI_PROJECT_ID:-}"
OPENAI_ORG_ID="${OPENAI_ORG_ID:-}"
USE_GOOGLE_OAUTH=false
if [[ -n "${GOOGLE_OAUTH_CLIENT_ID:-}" ]]; then
  USE_GOOGLE_OAUTH=true
  if [[ -z "${GOOGLE_OAUTH_CLIENT_SECRET:-}" ]]; then
    echo "Fatal: GOOGLE_OAUTH_CLIENT_SECRET is required when GOOGLE_OAUTH_CLIENT_ID is set." >&2
    exit 1
  fi
fi

# Prefer kind binary in this dir if present
if [[ -x "$SCRIPT_DIR/kind" ]]; then
  PATH="$SCRIPT_DIR:$PATH"
fi

BUILD_OPENCLAW_LOCAL=false
[[ "${OPENCLAW_BUILD_LOCAL:-}" == "1" ]] && BUILD_OPENCLAW_LOCAL=true

echo "==> Repo root: $REPO_ROOT"
echo "==> Cluster name: $CLUSTER_NAME"
echo "==> Kubeconfig: $KUBECONFIG_PATH"
echo "==> Namespace: $NAMESPACE"
echo "==> Google OAuth: $USE_GOOGLE_OAUTH"
echo "==> Build OpenClaw image locally: $BUILD_OPENCLAW_LOCAL"

mkdir -p "$SCRIPT_DIR"
export KUBECONFIG="$KUBECONFIG_PATH"

# Create cluster if it doesn't exist
if kind get kubeconfig --name "$CLUSTER_NAME" &>/dev/null; then
  echo "==> Cluster '$CLUSTER_NAME' already exists; writing kubeconfig to $KUBECONFIG_PATH"
  kind get kubeconfig --name "$CLUSTER_NAME" > "$KUBECONFIG_PATH"
else
  echo "==> Creating Kind cluster '$CLUSTER_NAME' (1 control-plane + 2 workers)..."
  kind create cluster \
    --name "$CLUSTER_NAME" \
    --config "$KIND_CONFIG"
fi

echo "==> Nodes:"
kubectl get nodes -o wide

CHART_PATH="$REPO_ROOT/charts/openclaw"
if [[ ! -d "$CHART_PATH" ]]; then
  echo "Fatal: chart not found at $CHART_PATH" >&2
  exit 1
fi

# Optional: build OpenClaw image from sibling openclaw repo and load into Kind
HELM_SET_IMAGE=""
if [[ "$BUILD_OPENCLAW_LOCAL" == true ]]; then
  OPENCLAW_SOURCE="$REPO_ROOT/../openclaw"
  if [[ ! -f "$OPENCLAW_SOURCE/Dockerfile" ]]; then
    echo "Fatal: OpenClaw source not found at $OPENCLAW_SOURCE (expected Dockerfile). Set OPENCLAW_BUILD_LOCAL=0 or clone openclaw beside openclaw-helm." >&2
    exit 1
  fi
  echo "==> Building OpenClaw image from $OPENCLAW_SOURCE..."
  docker build -t openclaw:kind-test "$OPENCLAW_SOURCE"
  echo "==> Loading OpenClaw image into Kind..."
  kind load docker-image openclaw:kind-test --name "$CLUSTER_NAME"
  HELM_SET_IMAGE="--set image.repository=openclaw --set image.tag=kind-test --set image.pullPolicy=IfNotPresent"
fi

if [[ "$USE_GOOGLE_OAUTH" == true ]]; then
  echo "==> Building gateway-nginx image..."
  docker build -t openclaw-gateway-nginx:latest "$REPO_ROOT/gateway-nginx"
  echo "==> Loading gateway-nginx image into Kind..."
  kind load docker-image openclaw-gateway-nginx:latest --name "$CLUSTER_NAME"
  COOKIE_SECRET="${COOKIE_SECRET:-$(python3 -c 'import os,base64; print(base64.urlsafe_b64encode(os.urandom(32)).decode())')}"
  VALUES_FILE="$SCRIPT_DIR/values-google-oauth.yaml"
  if [[ ! -f "$VALUES_FILE" ]]; then
    echo "Fatal: $VALUES_FILE not found." >&2
    exit 1
  fi
  echo "==> Installing OpenClaw from $CHART_PATH (with values-google-oauth.yaml)"
  HELM_SET_OPENAI=""
  [[ -n "$OPENAI_KEY" ]] && HELM_SET_OPENAI="$HELM_SET_OPENAI --set credentials.openaiApiKey=$OPENAI_KEY"
  [[ -n "$OPENAI_PROJECT_ID" ]] && HELM_SET_OPENAI="$HELM_SET_OPENAI --set credentials.openaiProjectId=$OPENAI_PROJECT_ID"
  [[ -n "$OPENAI_ORG_ID" ]] && HELM_SET_OPENAI="$HELM_SET_OPENAI --set credentials.openaiOrgId=$OPENAI_ORG_ID"
  helm upgrade --install openclaw "$CHART_PATH" \
    --namespace "$NAMESPACE" \
    -f "$VALUES_FILE" \
    $HELM_SET_IMAGE \
    --set "credentials.anthropicApiKey=$ANTHROPIC_KEY" \
    $HELM_SET_OPENAI \
    --set "gatewayOauth2Nginx.oauth2Proxy.clientId=$GOOGLE_OAUTH_CLIENT_ID" \
    --set "gatewayOauth2Nginx.oauth2Proxy.clientSecret=$GOOGLE_OAUTH_CLIENT_SECRET" \
    --set "gatewayOauth2Nginx.oauth2Proxy.cookieSecret=$COOKIE_SECRET" \
    --wait \
    --timeout 5m
  # Force gateway-nginx to use the image we just built (same tag = no pull, so restart to pick new image)
  echo "==> Restarting gateway-nginx to use newly built image..."
  kubectl rollout restart deployment/openclaw-gateway-nginx -n "$NAMESPACE" 2>/dev/null || true
  kubectl rollout status deployment/openclaw-gateway-nginx -n "$NAMESPACE" --timeout=120s 2>/dev/null || true
else
  echo "==> Installing OpenClaw from $CHART_PATH"
  HELM_SET_OPENAI=""
  [[ -n "$OPENAI_KEY" ]] && HELM_SET_OPENAI="$HELM_SET_OPENAI --set credentials.openaiApiKey=$OPENAI_KEY"
  [[ -n "$OPENAI_PROJECT_ID" ]] && HELM_SET_OPENAI="$HELM_SET_OPENAI --set credentials.openaiProjectId=$OPENAI_PROJECT_ID"
  [[ -n "$OPENAI_ORG_ID" ]] && HELM_SET_OPENAI="$HELM_SET_OPENAI --set credentials.openaiOrgId=$OPENAI_ORG_ID"
  helm upgrade --install openclaw "$CHART_PATH" \
    --namespace "$NAMESPACE" \
    $HELM_SET_IMAGE \
    --set "credentials.anthropicApiKey=$ANTHROPIC_KEY" \
    $HELM_SET_OPENAI \
    --wait \
    --timeout 5m
fi

echo "==> OpenClaw release status:"
helm status openclaw --namespace "$NAMESPACE"

echo "==> Pods:"
kubectl get pods -n "$NAMESPACE" -l app.kubernetes.io/name=openclaw -o wide
if [[ "$USE_GOOGLE_OAUTH" == true ]]; then
  kubectl get pods -n "$NAMESPACE" -l app.kubernetes.io/component=gateway-nginx -o wide 2>/dev/null || true
  kubectl get pods -n "$NAMESPACE" -l app.kubernetes.io/component=oauth2-proxy -o wide 2>/dev/null || true
fi

echo ""
echo "Done. To use this cluster:"
echo "  export KUBECONFIG=$KUBECONFIG_PATH"
if [[ "$USE_GOOGLE_OAUTH" == true ]]; then
  echo ""
  echo "Port-forward (run in a separate terminal and leave open):"
  echo "  ./kind-test/port-forward.sh"
  echo "Then open: http://localhost:4181  and sign in with Google (@gmail.com only)."
  echo "Chromium noVNC: http://localhost:8080/vnc.html  (password: openclaw-vnc)"
else
  echo "  ./kind-test/port-forward.sh   # gateway + noVNC"
fi
echo ""
echo "Use a real ANTHROPIC_API_KEY for full agent functionality."
