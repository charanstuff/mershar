#!/bin/sh
set -e

# OPENCLAW_GATEWAY_TOKEN can be set from env (K8s secret) or read from file
if [ -f /run/secrets/gateway-token ]; then
  export OPENCLAW_GATEWAY_TOKEN="$(cat /run/secrets/gateway-token)"
fi

# Use pod's first nameserver as resolver (works in Kind and any cluster); fallback if unset
if [ -z "${RESOLVER:-}" ] && [ -f /etc/resolv.conf ]; then
  RESOLVER=$(grep -m1 '^nameserver' /etc/resolv.conf | awk '{print $2}')
  export RESOLVER="${RESOLVER:-10.96.0.10}"
fi
export RESOLVER="${RESOLVER:-10.96.0.10}"

# Ensure TLS directory exists and generate a self-signed cert for localhost if none is mounted.
TLS_DIR="/etc/nginx/tls"
TLS_CERT="${TLS_DIR}/tls.crt"
TLS_KEY="${TLS_DIR}/tls.key"
mkdir -p "${TLS_DIR}"
if [ ! -f "${TLS_CERT}" ] || [ ! -f "${TLS_KEY}" ]; then
  echo "gateway-nginx: generating self-signed TLS certificate for localhost (dev use only)..."
  openssl req -x509 -nodes -newkey rsa:2048 -days 365 \
    -subj "/CN=localhost" \
    -keyout "${TLS_KEY}" \
    -out "${TLS_CERT}" >/dev/null 2>&1
fi

envsubst '${OPENCLAW_GATEWAY_TOKEN} ${OPENCLAW_GATEWAY_UPSTREAM} ${OAUTH2_PROXY_UPSTREAM} ${PORT} ${RESOLVER}' \
  < /etc/nginx/nginx.conf.tpl > /etc/nginx/nginx.conf
envsubst '${OPENCLAW_GATEWAY_TOKEN}' < /etc/nginx/gateway-token.json.tpl > /etc/nginx/gateway-token.json

exec nginx -g 'daemon off;'
