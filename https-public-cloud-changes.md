## Local HTTPS for Control UI (Kind / dev)

For local development, the goal is:

- Browser connects to the Control UI over **HTTPS** so:
  - The OpenClaw gateway token is encrypted in transit.
  - The browser sees a **secure context** (for WebCrypto / device identity).
  - `oauth2-proxy` can use **`cookieSecure: true`**.
- Inside the cluster, traffic between `gateway-nginx`, `oauth2-proxy`, and the OpenClaw gateway can stay on plain HTTP.

This repo achieves that by terminating TLS **inside the `gateway-nginx` container** on port **8443** with a self‑signed certificate.

### What was added

- `gateway-nginx/Dockerfile`
  - Install `openssl` so the container can generate a self‑signed certificate at startup.
  - Expose both ports:
    - `4181` – HTTP (internal + health checks).
    - `8443` – HTTPS (browser).
- `gateway-nginx/entrypoint.sh`
  - Ensures `/etc/nginx/tls` exists.
  - If `/etc/nginx/tls/tls.crt` or `/etc/nginx/tls/tls.key` is missing, generates a self‑signed cert:
    - Subject: `CN=localhost`
    - Valid for 365 days
  - Writes `nginx.conf` and starts nginx as before.
- `gateway-nginx/nginx.conf.tpl`
  - `server` block now listens on:
    - `listen ${PORT};` (HTTP, default 4181)
    - `listen 8443 ssl;` (HTTPS)
  - Uses the mounted/generated cert and key:
    - `ssl_certificate /etc/nginx/tls/tls.crt;`
    - `ssl_certificate_key /etc/nginx/tls/tls.key;`
- `openclaw-helm/charts/openclaw/templates/gateway-nginx-deployment.yaml`
  - Adds container port `https` on `8443`.
- `openclaw-helm/charts/openclaw/templates/gateway-nginx-service.yaml`
  - Exposes service port `8443` mapped to container port `https`.

### How to use HTTPS locally (Kind)

1. **Rebuild and push the nginx image (if you build locally)**

   From the repo root:

   ```bash
   # Build updated gateway-nginx image
   docker build -t openclaw-gateway-nginx:latest ./gateway-nginx

   # Load into Kind if you're using a local Kind cluster
   kind load docker-image openclaw-gateway-nginx:latest --name openclaw
   ```

   Adjust Kind cluster name as needed.

2. **Deploy with `gatewayOauth2Nginx.enabled: true`**

   (This is already wired in the `kind-test` values you use for OAuth + nginx.)

3. **Port-forward HTTPS to your machine**

   ```bash
   kubectl port-forward svc/openclaw-gateway-nginx 8443:8443
   ```

4. **Open the Control UI over HTTPS**

   - URL: `https://localhost:8443`
   - Because the certificate is self‑signed, your browser will warn the first time.
     - In dev, explicitly **trust** the cert / proceed to the site.

5. **Enable secure cookies in oauth2-proxy (dev)**

   In `values-*.yaml` used with Kind, set:

   - `gatewayOauth2Nginx.oauth2Proxy.cookieSecure: true`
   - `gatewayOauth2Nginx.oauth2Proxy.redirectUrl: "https://localhost:8443/oauth2/callback"`

   This keeps the OAuth cookie marked `Secure` and matches the HTTPS origin.

---

## Moving to public cloud (production-ish)

When moving from Kind/local to a public cloud (GKE, EKS, AKS, etc.), keep the same high‑level pattern:

- Terminate TLS **at the edge**.
- Keep `gateway-nginx` as the OAuth + token injector in front of the OpenClaw gateway.
- Keep internal hops (`gateway-nginx` → `oauth2-proxy` → gateway) on HTTP unless you have a requirement otherwise.

You have two main options:

### Option A: TLS at the cloud Ingress / LoadBalancer (recommended)

1. **Ingress / LB terminates TLS**

   - Configure your cloud Ingress controller (nginx, GKE Ingress, AWS ALB, etc.) or LoadBalancer:
     - Attach a real certificate (Let’s Encrypt / ACM / etc.) for `https://control.example.com`.
     - Forward HTTP traffic from the edge to the in‑cluster `openclaw-gateway-nginx` service on **4181**.

2. **DNS**

   - Point `control.example.com` at the Ingress / LoadBalancer hostname.

3. **oauth2-proxy configuration**

   - `gatewayOauth2Nginx.oauth2Proxy.cookieSecure: true`
   - `gatewayOauth2Nginx.oauth2Proxy.redirectUrl: "https://control.example.com/oauth2/callback"`
   - Ensure `ingress.hosts[0].host` (or equivalent) matches `control.example.com`.

4. **What changes in this repo?**

   - No structural changes are required beyond configuring the Ingress:
     - The existing HTTP listener on 4181 is enough.
     - The HTTPS listener on 8443 can remain unused or be removed later if you standardize on edge‑termination only.

### Option B: TLS directly in `gateway-nginx` (edge nginx)

If you prefer `gateway-nginx` itself to terminate TLS in the cloud (instead of ingress):

1. **Supply a real certificate via Kubernetes Secret**

   - Create a TLS secret (example):

     ```bash
     kubectl create secret tls gateway-nginx-tls \
       --cert=./fullchain.pem \
       --key=./privkey.pem \
       -n <namespace>
     ```

   - Mount that secret into the `gateway-nginx` pod at `/etc/nginx/tls`:
     - Add a `volumeMounts` entry for the nginx container.
     - Add a `volumes` entry referencing `gateway-nginx-tls`.
   - Because `entrypoint.sh` only *generates* a cert when the files are missing, the mounted real cert/key will be used instead of the self‑signed one.

2. **Expose HTTPS externally**

   - Use a LoadBalancer or NodePort service in front of `openclaw-gateway-nginx`:
     - Service port 443 → targetPort `https` (8443).
   - Point `control.example.com` DNS at that LoadBalancer.

3. **oauth2-proxy configuration**

   - Same as above:
     - `cookieSecure: true`
     - `redirectUrl` using `https://control.example.com/...`.

4. **Notes**

   - In this mode, the cloud LoadBalancer is just passing TCP 443 through to nginx; TLS is terminated inside the pod.
   - For most managed environments, **Option A (Ingress TLS)** is simpler operationally and integrates better with managed certificate tooling.

---

## Summary

- **Local dev / Kind**
  - HTTPS terminated at `gateway-nginx` on port 8443 with a self‑signed cert automatically generated at startup.
  - Use `https://localhost:8443` (port‑forwarded) for Control UI.
  - Enable `cookieSecure: true` and HTTPS redirect URLs in oauth2-proxy.

- **Public cloud**
  - Prefer terminating TLS at a cloud Ingress / LoadBalancer with a real certificate, forwarding HTTP to `gateway-nginx` on 4181.
  - Alternatively, mount a real TLS secret into `gateway-nginx` and expose its 8443 port directly behind a TCP LoadBalancer.

