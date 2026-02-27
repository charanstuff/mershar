#!/usr/bin/env bash
# Deploy a Kind cluster with multiple nodes and install OpenClaw via the Helm chart.
# Prerequisites: Docker running, kubectl and helm on PATH. Optionally kind on PATH
# or a kind binary at kind-test/kind (script will use it if present).
#
# Usage:
#   ./kind-test/deploy.sh [cluster-name] [--oauth=github|google] [--secure-cookie=true|false]
#
# Examples:
#   ./kind-test/deploy.sh                    # no OAuth (or use env: GITHUB_OAUTH_CLIENT_ID=...)
#   ./kind-test/deploy.sh --oauth=github    # GitHub OAuth (set GITHUB_OAUTH_CLIENT_ID + GITHUB_OAUTH_CLIENT_SECRET)
#   ./kind-test/deploy.sh mycluster --oauth=github
#   ./kind-test/deploy.sh --oauth=github --secure-cookie=false   # http://localhost (values-unsecure-* set this)
#   ./kind-test/deploy.sh --oauth=github --secure-cookie=true    # HTTPS production
#
# Optional env:
#   ANTHROPIC_API_KEY       - Anthropic API key (default: placeholder)
#   OPENAI_API_KEY          - OpenAI API key (use this instead of Anthropic for OpenAI models)
#   OPENAI_PROJECT_ID       - OpenAI project ID (required for sk-proj- keys, e.g. Default project)
#   OPENAI_ORG_ID           - OpenAI organization ID (optional, for multi-org)
#   OPENCLAW_NAMESPACE      - Kubernetes namespace (default: default)
#   OPENCLAW_BUILD_LOCAL    - If set to 1, build OpenClaw image from ../openclaw and load into Kind (use local image with header-auth)
#   GOOGLE_OAUTH_CLIENT_ID  - If set, use values-unsecure-google-auth.yaml (oauth2-proxy + nginx, @gmail.com only)
#   GOOGLE_OAUTH_CLIENT_SECRET - Required when GOOGLE_OAUTH_CLIENT_ID is set
#   GITHUB_OAUTH_CLIENT_ID  - If set, use values-unsecure-github-auth.yaml (oauth2-proxy + nginx, sign in with GitHub)
#   GITHUB_OAUTH_CLIENT_SECRET - Required when GITHUB_OAUTH_CLIENT_ID is set
#   COOKIE_SECRET           - Optional; auto-generated if unset and using OAuth
#
# Optional flags (OAuth only):
#   --secure-cookie=true    - oauth2-proxy cookie Secure flag (use for HTTPS)
#   --secure-cookie=false   - oauth2-proxy cookie Secure flag (use for http://localhost; values-unsecure-* set this)
#
# Kubeconfig is written to kind-test/kubeconfig (relative to repo root).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
KIND_CONFIG="$SCRIPT_DIR/kind-config.yaml"
KUBECONFIG_PATH="$SCRIPT_DIR/kubeconfig"
NAMESPACE="${OPENCLAW_NAMESPACE:-default}"
ANTHROPIC_KEY="${ANTHROPIC_API_KEY:-sk-ant-test-placeholder}"
OPENAI_KEY="${OPENAI_API_KEY:-}"
OPENAI_PROJECT_ID="${OPENAI_PROJECT_ID:-}"
OPENAI_ORG_ID="${OPENAI_ORG_ID:-}"

# Parse args: [cluster-name] [--oauth=github|google] [--secure-cookie=true|false]
CLUSTER_NAME="openclaw"
OAUTH_PARAM=""
SECURE_COOKIE_PARAM=""
for arg in "$@"; do
  if [[ "$arg" == --oauth=* ]]; then
    OAUTH_PARAM="${arg#--oauth=}"
  elif [[ "$arg" == --oauth-github ]]; then
    OAUTH_PARAM="github"
  elif [[ "$arg" == --oauth-google ]]; then
    OAUTH_PARAM="google"
  elif [[ "$arg" == --secure-cookie=* ]]; then
    SECURE_COOKIE_PARAM="${arg#--secure-cookie=}"
  elif [[ "$arg" != --* ]]; then
    # Positional arg (cluster name only if it doesn't look like a flag)
    CLUSTER_NAME="$arg"
  fi
done

USE_GOOGLE_OAUTH=false
USE_GITHUB_OAUTH=false
if [[ "$OAUTH_PARAM" == github ]]; then
  USE_GITHUB_OAUTH=true
  if [[ -z "${GITHUB_OAUTH_CLIENT_ID:-}" ]] || [[ -z "${GITHUB_OAUTH_CLIENT_SECRET:-}" ]]; then
    echo "Fatal: --oauth=github requires GITHUB_OAUTH_CLIENT_ID and GITHUB_OAUTH_CLIENT_SECRET." >&2
    exit 1
  fi
elif [[ "$OAUTH_PARAM" == google ]]; then
  USE_GOOGLE_OAUTH=true
  if [[ -z "${GOOGLE_OAUTH_CLIENT_ID:-}" ]] || [[ -z "${GOOGLE_OAUTH_CLIENT_SECRET:-}" ]]; then
    echo "Fatal: --oauth=google requires GOOGLE_OAUTH_CLIENT_ID and GOOGLE_OAUTH_CLIENT_SECRET." >&2
    exit 1
  fi
else
  # No --oauth=; use env to decide
  if [[ -n "${GOOGLE_OAUTH_CLIENT_ID:-}" ]]; then
    USE_GOOGLE_OAUTH=true
    if [[ -z "${GOOGLE_OAUTH_CLIENT_SECRET:-}" ]]; then
      echo "Fatal: GOOGLE_OAUTH_CLIENT_SECRET is required when GOOGLE_OAUTH_CLIENT_ID is set." >&2
      exit 1
    fi
  fi
  if [[ -n "${GITHUB_OAUTH_CLIENT_ID:-}" ]]; then
    if [[ "$USE_GOOGLE_OAUTH" == true ]]; then
      echo "Fatal: Set either GOOGLE_OAUTH_* or GITHUB_OAUTH_*, not both." >&2
      exit 1
    fi
    USE_GITHUB_OAUTH=true
    if [[ -z "${GITHUB_OAUTH_CLIENT_SECRET:-}" ]]; then
      echo "Fatal: GITHUB_OAUTH_CLIENT_SECRET is required when GITHUB_OAUTH_CLIENT_ID is set." >&2
      exit 1
    fi
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
echo "==> Google OAuth: $USE_GOOGLE_OAUTH  GitHub OAuth: $USE_GITHUB_OAUTH"
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

if [[ "$USE_GOOGLE_OAUTH" == true ]] || [[ "$USE_GITHUB_OAUTH" == true ]]; then
  GATEWAY_NGINX_DIR="$REPO_ROOT/gateway-nginx"
  [[ -d "$REPO_ROOT/../gateway-nginx" ]] && GATEWAY_NGINX_DIR="$REPO_ROOT/../gateway-nginx"
  echo "==> Building gateway-nginx image from $GATEWAY_NGINX_DIR..."
  docker build -t openclaw-gateway-nginx:latest "$GATEWAY_NGINX_DIR"
  echo "==> Loading gateway-nginx image into Kind..."
  kind load docker-image openclaw-gateway-nginx:latest --name "$CLUSTER_NAME"
  COOKIE_SECRET="${COOKIE_SECRET:-$(python3 -c 'import os,base64; print(base64.urlsafe_b64encode(os.urandom(32)).decode())')}"
  if [[ "$USE_GOOGLE_OAUTH" == true ]]; then
    VALUES_FILE="$SCRIPT_DIR/values-unsecure-google-auth.yaml"
    OAUTH_CLIENT_ID="$GOOGLE_OAUTH_CLIENT_ID"
    OAUTH_CLIENT_SECRET="$GOOGLE_OAUTH_CLIENT_SECRET"
  else
    VALUES_FILE="$SCRIPT_DIR/values-unsecure-github-auth.yaml"
    OAUTH_CLIENT_ID="$GITHUB_OAUTH_CLIENT_ID"
    OAUTH_CLIENT_SECRET="$GITHUB_OAUTH_CLIENT_SECRET"
  fi
  if [[ ! -f "$VALUES_FILE" ]]; then
    echo "Fatal: $VALUES_FILE not found." >&2
    exit 1
  fi
  # --secure-cookie: override oauth2-proxy cookieSecure (true for HTTPS, false for http://localhost)
  HELM_SET_COOKIE_SECURE=""
  if [[ -n "$SECURE_COOKIE_PARAM" ]]; then
    if [[ "$SECURE_COOKIE_PARAM" == true ]] || [[ "$SECURE_COOKIE_PARAM" == false ]]; then
      HELM_SET_COOKIE_SECURE="--set gatewayOauth2Nginx.oauth2Proxy.cookieSecure=$SECURE_COOKIE_PARAM"
    else
      echo "Fatal: --secure-cookie must be true or false, got: $SECURE_COOKIE_PARAM" >&2
      exit 1
    fi
  fi
  echo "==> Installing OpenClaw from $CHART_PATH (with $(basename "$VALUES_FILE"))"
  HELM_EXTRA=()
  [[ -n "$HELM_SET_IMAGE" ]] && HELM_EXTRA+=(--set "image.repository=openclaw" --set "image.tag=kind-test" --set "image.pullPolicy=IfNotPresent")
  [[ -n "$SECURE_COOKIE_PARAM" ]] && HELM_EXTRA+=(--set "gatewayOauth2Nginx.oauth2Proxy.cookieSecure=$SECURE_COOKIE_PARAM")
  [[ -n "$OPENAI_KEY" ]] && HELM_EXTRA+=(--set "credentials.openaiApiKey=$OPENAI_KEY")
  [[ -n "$OPENAI_PROJECT_ID" ]] && HELM_EXTRA+=(--set "credentials.openaiProjectId=$OPENAI_PROJECT_ID")
  [[ -n "$OPENAI_ORG_ID" ]] && HELM_EXTRA+=(--set "credentials.openaiOrgId=$OPENAI_ORG_ID")
  helm upgrade --install openclaw "$CHART_PATH" \
    --namespace "$NAMESPACE" \
    -f "$VALUES_FILE" \
    "${HELM_EXTRA[@]}" \
    --set "credentials.anthropicApiKey=$ANTHROPIC_KEY" \
    --set "gatewayOauth2Nginx.oauth2Proxy.clientId=$OAUTH_CLIENT_ID" \
    --set "gatewayOauth2Nginx.oauth2Proxy.clientSecret=$OAUTH_CLIENT_SECRET" \
    --set "gatewayOauth2Nginx.oauth2Proxy.cookieSecret=$COOKIE_SECRET" \
    --wait \
    --timeout 5m
  # Force gateway-nginx to use the image we just built (same tag = no pull, so restart to pick new image)
  echo "==> Restarting gateway-nginx to use newly built image..."
  kubectl rollout restart deployment/openclaw-gateway-nginx -n "$NAMESPACE" 2>/dev/null || true
  kubectl rollout status deployment/openclaw-gateway-nginx -n "$NAMESPACE" --timeout=120s 2>/dev/null || true
else
  echo "==> Installing OpenClaw from $CHART_PATH"
  HELM_EXTRA=()
  [[ -n "$HELM_SET_IMAGE" ]] && HELM_EXTRA+=(--set "image.repository=openclaw" --set "image.tag=kind-test" --set "image.pullPolicy=IfNotPresent")
  [[ -n "$OPENAI_KEY" ]] && HELM_EXTRA+=(--set "credentials.openaiApiKey=$OPENAI_KEY")
  [[ -n "$OPENAI_PROJECT_ID" ]] && HELM_EXTRA+=(--set "credentials.openaiProjectId=$OPENAI_PROJECT_ID")
  [[ -n "$OPENAI_ORG_ID" ]] && HELM_EXTRA+=(--set "credentials.openaiOrgId=$OPENAI_ORG_ID")
  helm upgrade --install openclaw "$CHART_PATH" \
    --namespace "$NAMESPACE" \
    "${HELM_EXTRA[@]}" \
    --set "credentials.anthropicApiKey=$ANTHROPIC_KEY" \
    --wait \
    --timeout 5m
fi

echo "==> OpenClaw release status:"
helm status openclaw --namespace "$NAMESPACE"

echo "==> Pods:"
kubectl get pods -n "$NAMESPACE" -l app.kubernetes.io/name=openclaw -o wide
if [[ "$USE_GOOGLE_OAUTH" == true ]] || [[ "$USE_GITHUB_OAUTH" == true ]]; then
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
elif [[ "$USE_GITHUB_OAUTH" == true ]]; then
  echo ""
  echo "Port-forward (run in a separate terminal and leave open):"
  echo "  ./kind-test/port-forward.sh"
  echo "Then open: http://localhost:4181  and sign in with GitHub."
  echo "Chromium noVNC: http://localhost:8080/vnc.html  (password: openclaw-vnc)"
else
  echo "  ./kind-test/port-forward.sh   # gateway + noVNC"
fi
echo ""
echo "Use a real ANTHROPIC_API_KEY for full agent functionality."
