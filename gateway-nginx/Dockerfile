# Nginx that: (1) auth_request to oauth2-proxy, (2) proxies to OpenClaw with Authorization: Bearer from env.
# Build: docker build -t openclaw-gateway-nginx:latest ./gateway-nginx
FROM nginx:1.27-alpine

# envsubst for templating and openssl for self-signed TLS generation (dev/local)
RUN apk add --no-cache envsubst openssl

COPY nginx.conf.tpl /etc/nginx/nginx.conf.tpl
COPY gateway-token.json.tpl /etc/nginx/gateway-token.json.tpl
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# HTTP (4181) for in-cluster use and health checks.
# HTTPS (8443) terminates TLS for the browser (self-signed by default).
EXPOSE 4181 8443
ENV PORT=4181 RESOLVER=10.96.0.10

ENTRYPOINT ["/entrypoint.sh"]
