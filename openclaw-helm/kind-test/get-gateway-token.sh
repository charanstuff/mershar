#!/usr/bin/env bash
# Print the OpenClaw gateway token for pasting into Control UI settings.
# Use this when you get "Missing scopes: api.responses.write" — paste the token
# in the Control UI dashboard settings so the UI uses token auth (full scopes).
#
# Usage: ./kind-test/get-gateway-token.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KUBECONFIG_PATH="$SCRIPT_DIR/kubeconfig"
NAMESPACE="${OPENCLAW_NAMESPACE:-default}"

if [[ ! -f "$KUBECONFIG_PATH" ]]; then
  echo "Fatal: kubeconfig not found at $KUBECONFIG_PATH. Run ./kind-test/deploy.sh first." >&2
  exit 1
fi

export KUBECONFIG="$KUBECONFIG_PATH"

TOKEN=$(kubectl get secret -n "$NAMESPACE" openclaw -o jsonpath='{.data.OPENCLAW_GATEWAY_TOKEN}' 2>/dev/null | base64 -d 2>/dev/null || true)
if [[ -z "$TOKEN" ]]; then
  echo "Fatal: could not read OPENCLAW_GATEWAY_TOKEN from secret openclaw in namespace $NAMESPACE." >&2
  exit 1
fi

echo "Gateway token (paste into Control UI → Settings → token):"
echo ""
echo "$TOKEN"
echo ""
echo "Steps: Open the Control UI, go to Settings, paste the token above, save. If you still see api.responses.write 401, clear site data for this origin and reload, then paste the token again."
