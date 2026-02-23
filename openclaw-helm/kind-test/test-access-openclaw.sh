#!/usr/bin/env bash
# Run a command in the OpenClaw pod (default: node dist/index.js --version).
# Uses kubeconfig in kind-test/kubeconfig. Run from repo root or kind-test/.
#
# Usage:
#   ./kind-test/test-access-openclaw.sh              # runs node dist/index.js --version
#   ./kind-test/test-access-openclaw.sh -- help      # runs node dist/index.js -- help
#   ./kind-test/test-access-openclaw.sh skill list   # runs node dist/index.js skill list

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

# Image runs "node dist/index.js gateway ..."; no openclaw binary in PATH. Use node dist/index.js.
if [[ $# -eq 0 ]]; then
  set -- node dist/index.js --version
else
  set -- node dist/index.js "$@"
fi

kubectl exec -n "$NAMESPACE" "$POD" -c openclaw -- "$@"
