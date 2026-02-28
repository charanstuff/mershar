#!/usr/bin/env bash
# Deploy OpenClaw on an existing cluster using aws/values/values-aws.yaml.
# Run from mershar repo root. Set env vars or pass --set overrides.
#
# Required env (or --set):
#   OPENCLAW_HOST          - e.g. openclaw.example.com or EC2 public DNS
#   OPENCLAW_TLS_SECRET    - K8s TLS secret name (default: openclaw-tls)
#   GITHUB_OAUTH_CLIENT_ID / GITHUB_OAUTH_CLIENT_SECRET  (or Google equivalents and use values-aws-google.yaml)
# Optional: COOKIE_SECRET (else chart may generate)
#
# Example:
#   export OPENCLAW_HOST=openclaw.example.com
#   export OPENCLAW_TLS_SECRET=openclaw-tls
#   export GITHUB_OAUTH_CLIENT_ID=xxx
#   export GITHUB_OAUTH_CLIENT_SECRET=yyy
#   ./aws/scripts/deploy-openclaw.sh

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
VALUES_FILE="${REPO_ROOT}/aws/values/values-aws.yaml"
CHART_PATH="${REPO_ROOT}/openclaw-helm/charts/openclaw"
NAMESPACE="${OPENCLAW_NAMESPACE:-default}"

if [[ ! -f "$VALUES_FILE" ]]; then
  echo "Fatal: values file not found: $VALUES_FILE" >&2
  exit 1
fi
if [[ ! -d "$CHART_PATH" ]]; then
  echo "Fatal: chart not found: $CHART_PATH" >&2
  exit 1
fi

HOST="${OPENCLAW_HOST:-}"
TLS_SECRET="${OPENCLAW_TLS_SECRET:-openclaw-tls}"
if [[ -z "$HOST" ]]; then
  echo "Fatal: set OPENCLAW_HOST (e.g. openclaw.example.com or EC2 public DNS)" >&2
  exit 1
fi

REDIRECT_URL="https://${HOST}/oauth2/callback"

EXTRA_SET=()
EXTRA_SET+=(--set "ingress.hosts[0].host=$HOST")
EXTRA_SET+=(--set "ingress.tls[0].secretName=$TLS_SECRET")
EXTRA_SET+=(--set "ingress.tls[0].hosts[0]=$HOST")
EXTRA_SET+=(--set "gatewayOauth2Nginx.oauth2Proxy.redirectUrl=$REDIRECT_URL")
EXTRA_SET+=(--set "gatewayOauth2Nginx.oauth2Proxy.cookieSecure=true")

if [[ -n "${GITHUB_OAUTH_CLIENT_ID:-}" ]]; then
  EXTRA_SET+=(--set "gatewayOauth2Nginx.oauth2Proxy.clientId=$GITHUB_OAUTH_CLIENT_ID")
  EXTRA_SET+=(--set "gatewayOauth2Nginx.oauth2Proxy.provider=github")
fi
if [[ -n "${GITHUB_OAUTH_CLIENT_SECRET:-}" ]]; then
  EXTRA_SET+=(--set "gatewayOauth2Nginx.oauth2Proxy.clientSecret=$GITHUB_OAUTH_CLIENT_SECRET")
fi
if [[ -n "${GOOGLE_OAUTH_CLIENT_ID:-}" ]]; then
  EXTRA_SET+=(--set "gatewayOauth2Nginx.oauth2Proxy.clientId=$GOOGLE_OAUTH_CLIENT_ID")
  EXTRA_SET+=(--set "gatewayOauth2Nginx.oauth2Proxy.provider=google")
fi
if [[ -n "${GOOGLE_OAUTH_CLIENT_SECRET:-}" ]]; then
  EXTRA_SET+=(--set "gatewayOauth2Nginx.oauth2Proxy.clientSecret=$GOOGLE_OAUTH_CLIENT_SECRET")
fi
if [[ -n "${COOKIE_SECRET:-}" ]]; then
  EXTRA_SET+=(--set "gatewayOauth2Nginx.oauth2Proxy.cookieSecret=$COOKIE_SECRET")
fi

echo "Deploying OpenClaw with host=$HOST, tlsSecret=$TLS_SECRET"
helm upgrade --install openclaw "$CHART_PATH" \
  -f "$VALUES_FILE" \
  "${EXTRA_SET[@]}" \
  -n "$NAMESPACE" \
  "$@"

echo ""
echo "Gateway:  https://${HOST}/"
echo "noVNC:    https://${HOST}/vnc/   and   https://${HOST}/vnc/vnc.html"
