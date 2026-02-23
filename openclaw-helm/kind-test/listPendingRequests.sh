#!/usr/bin/env bash
# List pending device pairing requests (for "pairing required" 1008).
# Run approveRequest.sh with a Request ID from this list to approve the device.
#
# Usage: ./kind-test/listPendingRequests.sh

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

kubectl exec -n "$NAMESPACE" "$POD" -c openclaw -- node dist/index.js devices list
