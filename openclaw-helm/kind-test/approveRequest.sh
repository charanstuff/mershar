#!/usr/bin/env bash
# Approve a pending device pairing request (fixes "pairing required" 1008).
# Get the Request ID from ./kind-test/listPendingRequests.sh (first column under "Pending").
#
# Usage: ./kind-test/approveRequest.sh [request-id]
#   If request-id is omitted, approves the latest pending request (if the CLI supports it).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KUBECONFIG_PATH="$SCRIPT_DIR/kubeconfig"
NAMESPACE="${OPENCLAW_NAMESPACE:-default}"

if [[ ! -f "$KUBECONFIG_PATH" ]]; then
  echo "Fatal: kubeconfig not found at $KUBECONFIG_PATH. Create the cluster first: ./kind-test/deploy.sh" >&2
  exit 1
fi

export KUBECONFIG="$KUBECONFIG_PATH"

# Main OpenClaw pod (2/2 containers: openclaw + chromium), not oauth2-proxy or gateway-nginx
POD=$(kubectl get pods -n "$NAMESPACE" -l app.kubernetes.io/name=openclaw --no-headers 2>/dev/null | awk '$2=="2/2" {print $1; exit}')
if [[ -z "$POD" ]]; then
  echo "Fatal: no OpenClaw app pod found in namespace $NAMESPACE (expected pod with 2/2 containers)" >&2
  exit 1
fi

REQUEST_ID="${1:-}"
if [[ -z "$REQUEST_ID" ]]; then
  echo "Usage: $0 <request-id>" >&2
  echo "Get request IDs with: ./kind-test/listPendingRequests.sh" >&2
  exit 1
fi

kubectl exec -n "$NAMESPACE" "$POD" -c openclaw -- node dist/index.js devices approve "$REQUEST_ID"
