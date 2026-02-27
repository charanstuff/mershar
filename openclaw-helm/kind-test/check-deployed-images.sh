#!/usr/bin/env bash
# Check which images are deployed and show OpenClaw logs for debugging.
# Run from repo root: ./kind-test/check-deployed-images.sh
# Requires: KUBECONFIG or run with repo as cwd (uses kind-test/kubeconfig).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
KUBECONFIG_PATH="${KUBECONFIG:-$SCRIPT_DIR/kubeconfig}"
NAMESPACE="${OPENCLAW_NAMESPACE:-default}"

export KUBECONFIG="$KUBECONFIG_PATH"

echo "=== KUBECONFIG ==="
echo "$KUBECONFIG"
echo ""

echo "=== OPENCLAW DEPLOYMENT (image) ==="
OPENCLAW_IMAGE=$(kubectl -n "$NAMESPACE" get deploy openclaw -o jsonpath='{.spec.template.spec.containers[0].image}' 2>/dev/null || echo "<deployment not found>")
echo "OpenClaw image: $OPENCLAW_IMAGE"
if [[ "$OPENCLAW_IMAGE" == "openclaw:kind-test" ]]; then
  echo "  -> Local build (OPENCLAW_BUILD_LOCAL=1) is in use. Header-token patch should be active."
else
  echo "  -> Default/registry image. To use your patched OpenClaw, run deploy with: export OPENCLAW_BUILD_LOCAL=1"
fi
echo ""

echo "=== GATEWAY-NGINX DEPLOYMENT (image) ==="
NGINX_IMAGE=$(kubectl -n "$NAMESPACE" get deploy openclaw-gateway-nginx -o jsonpath='{.spec.template.spec.containers[0].image}' 2>/dev/null || echo "<not found>")
echo "Gateway nginx image: $NGINX_IMAGE"
echo ""

echo "=== OAUTH2-PROXY DEPLOYMENT (image) ==="
OAUTH_IMAGE=$(kubectl -n "$NAMESPACE" get deploy openclaw-oauth2-proxy -o jsonpath='{.spec.template.spec.containers[0].image}' 2>/dev/null || echo "<not found>")
echo "OAuth2-proxy image: $OAUTH_IMAGE"
echo ""

echo "=== OPENCLAW POD LOGS (last 30 lines, openclaw container) ==="
kubectl -n "$NAMESPACE" logs deploy/openclaw -c openclaw --tail=30 2>/dev/null || echo "(no logs)"
echo ""

echo "=== WHERE TO DEBUG OPENCLAW WS AUTH ==="
echo "  File: $REPO_ROOT/openclaw/src/gateway/server/ws-connection/message-handler.ts"
echo "  Look for the block: \"Fallback: when the Control UI or WebChat connects via a reverse proxy\""
echo "  Add a log to confirm the fallback runs, e.g.:"
echo "    logWsControl.info(\"ws-auth\", { hasHeaderToken: Boolean(headerToken), isControlUi, isWebchat });"
echo "  Then rebuild and redeploy with OPENCLAW_BUILD_LOCAL=1"
