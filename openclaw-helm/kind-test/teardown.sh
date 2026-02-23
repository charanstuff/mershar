#!/usr/bin/env bash
# Delete the Kind cluster. Use the same cluster name as deploy.sh (default: openclaw).
#
# Usage:
#   ./kind-test/teardown.sh           # deletes cluster "openclaw"
#   ./kind-test/teardown.sh mycluster # deletes cluster "mycluster"
#
# After teardown, run ./kind-test/deploy.sh to create a fresh cluster with OpenClaw.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLUSTER_NAME="${1:-openclaw}"

if [[ -x "$SCRIPT_DIR/kind" ]]; then
  PATH="$SCRIPT_DIR:$PATH"
fi

kind delete cluster --name "$CLUSTER_NAME"
echo "Cluster $CLUSTER_NAME deleted. Run ./kind-test/deploy.sh to create a fresh one."
