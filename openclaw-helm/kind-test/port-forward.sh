#!/usr/bin/env bash
# Port-forward so you can reach OpenClaw and (optionally) Chromium noVNC.
# When gatewayOauth2Nginx is enabled: forwards 4181 (auth gateway) and 8080 (noVNC).
# Otherwise: forwards 18789 (gateway) and 8080 (noVNC). Leave the terminal open.
#
# Usage: ./kind-test/port-forward.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KUBECONFIG_PATH="$SCRIPT_DIR/kubeconfig"
NAMESPACE="${OPENCLAW_NAMESPACE:-default}"

if [[ ! -f "$KUBECONFIG_PATH" ]]; then
  echo "Fatal: kubeconfig not found at $KUBECONFIG_PATH. Create the cluster first: ./kind-test/deploy.sh" >&2
  exit 1
fi

export KUBECONFIG="$KUBECONFIG_PATH"

POD=$(kubectl get pods -n "$NAMESPACE" -l app.kubernetes.io/name=openclaw -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)
if [[ -z "$POD" ]]; then
  echo "Fatal: no OpenClaw pod found in namespace $NAMESPACE" >&2
  exit 1
fi

# If gateway-nginx service exists, we're in OAuth mode: forward 4181 (nginx) and 8080 (pod)
if kubectl get svc -n "$NAMESPACE" openclaw-gateway-nginx &>/dev/null; then
  GATEWAY_TOKEN=$(kubectl get secret -n "$NAMESPACE" openclaw -o jsonpath='{.data.OPENCLAW_GATEWAY_TOKEN}' 2>/dev/null | base64 -d 2>/dev/null || true)
  echo "OAuth mode: forwarding gateway-nginx (4181) and Chromium noVNC (8080)."
  echo ""
  echo "OpenClaw (sign in with Google @gmail.com):"
  echo "  http://localhost:4181"
  if [[ -n "${GATEWAY_TOKEN:-}" ]]; then
    echo ""
    echo "If the dashboard shows 'gateway token missing', paste this token once in Settings → Control (gateway token) — no token in URL."
    echo "  $GATEWAY_TOKEN"
  fi
  echo ""
  echo "Chromium noVNC:"
  echo "  http://localhost:8080/vnc.html"
  echo "  Password: openclaw-vnc"
  echo ""
  kubectl port-forward -n "$NAMESPACE" svc/openclaw-gateway-nginx 4181:4181 &
  kubectl port-forward -n "$NAMESPACE" "pod/$POD" 8080:8080 &
  wait
else
  TOKEN=$(kubectl get secret -n "$NAMESPACE" openclaw -o jsonpath='{.data.OPENCLAW_GATEWAY_TOKEN}' | base64 -d)
  echo "Forwarding gateway (18789) and noVNC (8080) from pod $POD."
  echo ""
  echo "Gateway / Canvas:"
  echo "  http://localhost:18789/__openclaw__/canvas/?token=$TOKEN"
  echo "  http://localhost:18789 (API/WS)"
  echo ""
  echo "Chromium noVNC (only when chromium.visibleMode is true):"
  echo "  http://localhost:8080/vnc.html"
  echo "  Password: openclaw-vnc"
  echo ""
  kubectl port-forward -n "$NAMESPACE" "pod/$POD" 18789:18789 8080:8080
fi
