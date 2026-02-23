#!/usr/bin/env bash
# Run OpenClaw TUI (terminal UI) inside the OpenClaw pod to test the gateway + model path.
# Uses the same env (OPENAI_API_KEY, OPENAI_PROJECT_ID, etc.) as the gateway. If TUI works
# here but Chat in the browser fails with "invalid x-api-key", the issue is in the web path.
#
# Usage: ./kind-test/run-tui-in-pod.sh
#
# Requires: KUBECONFIG or kind-test/kubeconfig. Run from repo root or kind-test/.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KUBECONFIG_PATH="$SCRIPT_DIR/kubeconfig"
NAMESPACE="${OPENCLAW_NAMESPACE:-default}"

if [[ ! -f "$KUBECONFIG_PATH" ]]; then
  echo "Fatal: kubeconfig not found at $KUBECONFIG_PATH. Create the cluster first: ./kind-test/deploy.sh" >&2
  exit 1
fi

export KUBECONFIG="$KUBECONFIG_PATH"

# Main OpenClaw app pod (2/2 containers: openclaw + chromium), not oauth2-proxy or gateway-nginx
POD=$(kubectl get pods -n "$NAMESPACE" -l app.kubernetes.io/name=openclaw --no-headers 2>/dev/null | awk '$2=="2/2" {print $1; exit}')
if [[ -z "$POD" ]]; then
  echo "Fatal: no OpenClaw app pod found in namespace $NAMESPACE (expected pod with 2/2 containers)" >&2
  exit 1
fi

echo "Starting OpenClaw TUI in pod $POD (connects to gateway on 127.0.0.1:18789)..."
echo "If TUI works here, credentials are fine; if it fails with invalid x-api-key, the issue is gateway/OpenAI."
echo "Exit TUI: Ctrl+D or /quit"
echo ""

# TUI needs -it for interactive; token comes from pod env (OPENCLAW_GATEWAY_TOKEN)
kubectl exec -it -n "$NAMESPACE" "$POD" -c openclaw -- \
  sh -c 'node dist/index.js tui --url ws://127.0.0.1:18789 --token "$OPENCLAW_GATEWAY_TOKEN"'
