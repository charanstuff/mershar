# Security and Default Changes

This document describes the security-related changes made to the OpenClaw Helm chart, the issues and trade-offs involved, and how to mitigate them.

---

## Summary of Changes

1. **Init container** — Runs as non-root (UID 1000) with a tight securityContext; the `chown` step was removed and ownership is handled via pod `fsGroup`.
2. **Chromium sidecar** — Remote debugging binds to `127.0.0.1` by default (configurable); `--no-sandbox` is configurable (default remains `true`).
3. **Gateway bind** — Default is `lan` so the gateway is reachable for port-forward, ingress, and other pods; the issues with using `lan` are documented below.

---

## 1. Init Container (Non-Root, No `chown`)

### What changed

- The `init-config` container no longer runs as root. It runs as UID 1000 (same as the main OpenClaw container) using a dedicated `initContainer.securityContext` in values.
- The `chown -R 1000:1000` step was removed. The pod’s `fsGroup: 1000` ensures the data volume is writable by GID 1000, so files created by the init are already owned correctly.

### Issues and considerations

| Issue | Likelihood | Mitigation |
|-------|------------|------------|
| **Volume not writable by UID 1000** | Low | The pod uses `fsGroup: 1000`, so the mounted volume is group-writable. If you override `podSecurityContext` and remove or change `fsGroup`, or run the init as a different user, the init may not be able to write. | Keep `podSecurityContext.fsGroup` set to 1000 (or match your `runAsGroup`), and don’t override `initContainer.securityContext.runAsUser` to a user that can’t write to that group. |
| **Existing PVC created when init was root** | Low | If the PVC was first used when the init ran as root, existing files might have been created with different ownership. With `fsGroup: 1000` the main app (UID 1000) could still read/write in most cases. The first run after upgrading might hit permission errors on rare setups. | If you see permission errors after upgrading, fix volume ownership once (e.g. run a one-off pod as root to `chown -R 1000:1000` on the volume), or recreate the PVC. |
| **Read-only root filesystem** | Low | The init has `readOnlyRootFilesystem: false` so it can run `node` and write under the mounted volume. If the image or a stricter policy enforces a read-only root filesystem, the init could fail. | Keep `readOnlyRootFilesystem: false` for the init unless the image is explicitly designed for read-only root. |

---

## 2. Chromium: CDP Bound to 127.0.0.1

### What changed

- `chromium.remoteDebuggingAddress` was added (default `127.0.0.1`). The Chromium sidecar listens for CDP only on loopback inside the pod instead of `0.0.0.0`.
- OpenClaw still connects to `http://localhost:9222` (same pod, same network namespace), so browser automation is unchanged.

### Issues and considerations

| Issue | Likelihood | Mitigation |
|-------|------------|------------|
| **OpenClaw can’t reach CDP** | Very low | OpenClaw and Chromium share the same pod; `localhost` in the config is correct. No change is required for normal browser automation. | None if you didn’t change the CDP URL; it remains `http://localhost:9222`. |
| **Debugging CDP from outside the pod** | Expected | If you were connecting to the Chromium debug port from outside the pod (e.g. `kubectl port-forward ... 9222:9222` and a browser devtools client), that can fail because Chromium now listens only on loopback inside the pod. | For external CDP debugging, set `chromium.remoteDebuggingAddress: "0.0.0.0"` in values (and accept that anything that can reach the pod on 9222 can use CDP). |

---

## 3. Chromium: Configurable `--no-sandbox`

### What changed

- `chromium.noSandbox` was added (default `true`). The `--no-sandbox` flag is only passed when this is true, so operators can try enabling the sandbox where supported.

### Issues and considerations

| Issue | Likelihood | Mitigation |
|-------|------------|------------|
| **Chromium fails with sandbox enabled** | Possible | Many Chromium-in-Docker/Kubernetes images expect `--no-sandbox` (e.g. missing user namespaces, shared PID namespace). If you set `chromium.noSandbox: false` for security, Chromium may crash or fail to start. | Keep the default `noSandbox: true` unless you’ve verified the image and cluster support Chromium’s sandbox. Document that `noSandbox: false` can break in some environments. |
| **Worse security when sandbox is disabled** | Known | With `noSandbox: true` (default), a compromise in the browser process can have more impact. This was already the case; the change only made the flag configurable. | Optional hardening: set `noSandbox: false` only in environments where you’ve confirmed it works. |

---

## 4. Gateway Bind: Default `lan`

### What changed

- The default `openclaw.bind` is `lan` so the gateway listens on all interfaces. This is required for port-forward, ingress, and other pods in the cluster to reach OpenClaw.

### Issues and considerations

| Issue | Mitigation |
|-------|------------|
| **Gateway is reachable on the pod network** | Any client that can reach the pod IP or the Service can try to connect. If the gateway has no or weak auth, they could use or abuse the agent (LLM calls, browser automation). | Use gateway authentication (e.g. `OPENCLAW_GATEWAY_TOKEN` / `gatewayToken` in the chart). Keep the token in a Secret. Optionally use NetworkPolicies to restrict which namespaces/pods can talk to the OpenClaw Service. |
| **Accidental exposure via Ingress** | If Ingress (or similar) is enabled without tightening access, the gateway can become reachable from outside the cluster. | Only enable Ingress when needed. Use TLS and auth (e.g. ensure the gateway token is required), and restrict who can reach it (e.g. IP allowlists, VPN-only). |
| **Same cluster, other tenants** | In multi-tenant or shared clusters, any workload that can reach the OpenClaw Service can connect when bind is `lan`. | Use NetworkPolicies to limit which namespaces/pods can talk to the OpenClaw Service. Prefer a dedicated namespace and avoid broad Service exposure. |
| **Default vs explicit choice** | With default `lan`, new installs get network access without explicitly opting in. Operators may not realize the gateway is reachable and may skip auth or network lockdown. | Document that `lan` implies network exposure and that gateway token and NetworkPolicies (and careful Ingress use) are recommended. |

---

## Quick reference

| Area | Default / behavior | Main risk | Mitigation |
|------|-------------------|-----------|------------|
| Init container | Non-root (1000), no chown | Old PVC or custom security context | Keep `fsGroup: 1000`; fix volume ownership or recreate PVC if needed |
| Chromium CDP | `127.0.0.1` | No normal impact | Set `remoteDebuggingAddress: "0.0.0.0"` only if you need external CDP access |
| Chromium sandbox | `noSandbox: true` | Sandbox on can break in some runtimes | Keep default; set `noSandbox: false` only where verified |
| Gateway bind | `lan` | Exposure and abuse if auth/network weak | Use gateway token; NetworkPolicies; careful Ingress use |
