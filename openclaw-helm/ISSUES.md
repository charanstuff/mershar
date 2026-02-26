# OpenClaw Helm / Kind-test – open issues

Items to address later. Not necessarily bugs; includes hardening and ops notes.

---

## Gateway token (nginx → OpenClaw) – security hardening

**Context:** When using gateway-nginx + OAuth (e.g. `values-unsecure-github-auth.yaml`), nginx injects the gateway token when proxying to OpenClaw. OpenClaw reads the token from (1) request headers (`Authorization`, `x-api-key`, `x-openclaw-api-key`) or (2) **query string** (`?token=...`) on the internal nginx → OpenClaw request only. The browser never sees or sends the token.

**Current risk assessment:** Low for “browser outside, nginx + OAuth + OpenClaw on same server” — the token is only on the internal hop and is not sent to the client.

**To address later:**

1. **Logging**
   - Ensure nginx and OpenClaw do **not** log the full request URL (or redact/omit the `token` query parameter) so the gateway token does not appear in access or app logs.
   - If any log format includes `$request` or equivalent, confirm it does not expose the token.

2. **OpenClaw not directly exposed**
   - OpenClaw should only be reachable from nginx (e.g. localhost or cluster-internal), not directly from the internet. Verify OpenClaw is not bound to a public interface or exposed via another route without OAuth + token.

3. **Optional: prefer headers over query**
   - Today the token often reaches OpenClaw via query string because headers were not reliably forwarded on WebSocket upgrade. If nginx/stack is later fixed so `Authorization` or `x-api-key` are consistently sent to OpenClaw, consider documenting that and optionally deprecating or down-prioritizing the query-string fallback for consistency (headers are easier to keep out of logs by default).

---

*Last updated: 2026-02-26*
