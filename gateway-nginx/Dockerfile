# Nginx that: (1) auth_request to oauth2-proxy, (2) proxies to OpenClaw with Authorization: Bearer from env.
# Build: docker build -t openclaw-gateway-nginx:latest ./gateway-nginx
FROM nginx:1.27-alpine

RUN apk add --no-cache envsubst

COPY nginx.conf.tpl /etc/nginx/nginx.conf.tpl
COPY gateway-token.json.tpl /etc/nginx/gateway-token.json.tpl
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

EXPOSE 4181
ENV PORT=4181 RESOLVER=10.96.0.10

ENTRYPOINT ["/entrypoint.sh"]
