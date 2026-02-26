# Injected at runtime: OPENCLAW_GATEWAY_TOKEN, OPENCLAW_GATEWAY_UPSTREAM, OAUTH2_PROXY_UPSTREAM, PORT, RESOLVER
worker_processes 1;
error_log /dev/stderr info;
events { worker_connections 64; }
http {
  resolver ${RESOLVER} valid=10s ipv6=off;
  access_log /dev/stdout;
  include /etc/nginx/mime.types;
  default_type application/octet-stream;
  client_max_body_size 20m;

  # Upstreams (FQDN so resolver works)
  upstream openclaw_backend {
    server ${OPENCLAW_GATEWAY_UPSTREAM};
    keepalive 4;
  }
  upstream oauth2_proxy_backend {
    server ${OAUTH2_PROXY_UPSTREAM};
    keepalive 4;
  }

  # Append gateway token to query string for OpenClaw
  map $args $args_with_token {
    default "${args}&token=${OPENCLAW_GATEWAY_TOKEN}";
    ''       "token=${OPENCLAW_GATEWAY_TOKEN}";
  }
  map $http_upgrade $connection_upgrade {
    default upgrade;
    ''       "";
  }
  # Always inject gateway token when proxying to OpenClaw (do not pass through client
  # Authorization/x-api-key). Otherwise after Google "is it you?" the browser can send
  # an OAuth Bearer header and nginx would forward it, causing token_mismatch.
  map $scheme $injected_bearer {
    default "Bearer ${OPENCLAW_GATEWAY_TOKEN}";
  }
  map $scheme $injected_x_api_key {
    default "${OPENCLAW_GATEWAY_TOKEN}";
  }

  server {
    listen ${PORT};
    server_name _;

    # Health (no auth)
    location = /health {
      add_header Content-Type text/plain;
      return 200 "ok\n";
    }

    # OAuth2 proxy callback and internal paths
    location /oauth2/ {
      proxy_pass http://oauth2_proxy_backend;
      proxy_http_version 1.1;
      proxy_set_header Host $host;
      proxy_set_header X-Real-IP $remote_addr;
      proxy_set_header X-Scheme $scheme;
      proxy_set_header X-Auth-Request-Redirect $request_uri;
    }

    # Gateway token JSON for frontend (OAuth-protected)
    location = /__openclaw__/gateway-token {
      auth_request /oauth2/auth;
      auth_request_set $auth_user $upstream_http_x_auth_request_user;
      error_page 401 = /oauth2/sign_in?redirect=$scheme://$host$request_uri;
      add_header Content-Type application/json;
      alias /etc/nginx/gateway-token.json;
    }

    # All other traffic: OAuth then proxy to OpenClaw with gateway token
    location / {
      auth_request /oauth2/auth;
      auth_request_set $auth_user $upstream_http_x_auth_request_user;
      error_page 401 = /oauth2/sign_in?redirect=$scheme://$host$request_uri;

      set $backend_request $uri?$args_with_token;
      proxy_pass http://openclaw_backend$backend_request;
      proxy_http_version 1.1;
      proxy_set_header Host $host;
      proxy_set_header X-Real-IP $remote_addr;
      proxy_set_header X-Scheme $scheme;
      proxy_set_header X-Auth-Request-User $auth_user;
      # Gateway auth: always inject (never pass through client Authorization to avoid OAuth token leaking)
      proxy_set_header Authorization $injected_bearer;
      proxy_set_header x-api-key $injected_x_api_key;
      proxy_set_header X-API-Key $injected_x_api_key;
      proxy_set_header X-OpenClaw-API-Key $injected_x_api_key;
      # WebSocket for gateway
      proxy_set_header Upgrade $http_upgrade;
      proxy_set_header Connection $connection_upgrade;
      proxy_read_timeout 86400;
    }

    # OAuth2 auth subrequest (must forward client Cookie so oauth2-proxy can validate session)
    location = /oauth2/auth {
      internal;
      proxy_pass http://oauth2_proxy_backend/oauth2/auth;
      proxy_http_version 1.1;
      proxy_set_header Host $host;
      proxy_set_header X-Real-IP $remote_addr;
      proxy_set_header X-Scheme $scheme;
      proxy_set_header X-Original-URI $request_uri;
      proxy_set_header Cookie $http_cookie;
      proxy_set_header Content-Length "";
      proxy_pass_request_body off;
    }
  }
}
