# Step-by-Step Plan: Current Code → Design (Requirements + FullDiagram)

This plan aligns the current OpenClaw + openclaw-helm codebase with **Requirements.md**, **Design.md**, and **FullDiagram.png**: multi-tenant platform, Firecracker-backed sandboxes, CRD-driven control plane, queue-based work distribution, tool broker, and durable state.

**Scope:** Changes span **openclaw** (app/gateway), **openclaw-helm** (charts, CRDs, operators), and **new components** (orchestrator, queue, broker). **Dockerfiles** for OpenClaw, gateway-nginx, and gateway-auth-proxy remain valid; new images (e.g. orchestrator, init-supervisor) will need Dockerfiles. **gateway-auth-proxy** is currently a placeholder; it can be implemented as the edge auth layer or merged with Envoy/nginx.

---

## Current State vs Design (Gap Summary)

| Design component | Current state | Target |
|------------------|---------------|--------|
| **API Gateway** | gateway-nginx + oauth2-proxy (no tenant routing) | Envoy or nginx with TLS, AuthN/Z, **tenant ID resolution** and routing |
| **Tenant Orchestrator** | None | Validate quotas, classify work, decompose requests into task units, wake idle tenants |
| **Scheduler / Placement** | None | Map tasks to ExecutorPools/sandboxes; quota, risk-class, capacity |
| **CRDs + Operator** | None | Tenant, Swarm, Sandbox, ExecutorPool; operator reconciles to K8s resources |
| **KEDA** | None | Scale ExecutorPools from queue depth; scale to zero |
| **Queue / Task bus** | In-memory only in gateway | NATS / Redis Streams / Kafka / Temporal — durable, tenant-scoped |
| **Tool Proxy / Secrets Broker** | None | Policy check, short-lived scoped creds, audit |
| **State Services** | Local dir + config | Postgres (metadata), object store / RWX FS (artifacts, checkpoints) |
| **Compute: Sandboxes** | Single OpenClaw pod | Pod per Sandbox with **Kata RuntimeClass (Firecracker)** |
| **Compute: Init/Supervisor** | None | Lightweight init in microVM starts N OpenClaw executors |
| **Compute: ExecutorPools** | Single process | Per–agent-type pools; multiple executors per sandbox; shard assignment |
| **Tenant isolation** | No tenant model | Namespaces, quotas, network policy, storage isolation |

---

## Requirement Priorities (from Requirements.md §12)

- **Must Have:** Tenant isolation, sandbox provisioning, executor pools, queue-based work distribution, durable state, tool broker, autoscaling, audit logging.
- **Should Have:** Warm resume, high-risk isolation, fairness, placement policies, pause/drain.
- **Nice to Have:** Premium tenancy, snapshot tiering, predictive scaling, cost-aware placement.

The plan below orders work so **Must Have** items are achievable first, with verification at each step.

---

## Phase 0: Foundation and Terminology

**Goal:** Align codebase and docs with design terms; no behavioral change yet.

| Step | Action | Verification |
|------|--------|--------------|
| 0.1 | Add a short **architecture doc** (or section in Design.md) that maps: Tenant → namespace/customer, Swarm → workload request, Sandbox → microVM pod, ExecutorPool → scalable group of OpenClaw processes, Shard → partition of work. | Doc exists; team agrees on terms. |
| 0.2 | In openclaw, introduce a **tenant ID** in gateway auth/session resolution (e.g. from header or OAuth claim). Pass tenant ID through request context; log it (not secrets). | One request path (e.g. WS connect or one HTTP route) logs `tenant_id` in a structured log. |
| 0.3 | In openclaw-helm, add a **placeholder values section** for future control-plane components: `orchestrator`, `queue`, `state`, `broker`, `crds`, `keda`, `runtimeClass`. | `helm template` succeeds; values are optional/disabled. |

---

## Phase 1: Control-Plane Foundation — Gateway, Tenant, State

**Goal:** All requests go through a single edge that resolves tenant; minimal durable state exists.

| Step | Action | Verification |
|------|--------|--------------|
| 1.1 | **Tenant resolution at edge:** In gateway-nginx (or Envoy if you switch), add tenant ID from OAuth claim or header (e.g. `X-Tenant-ID`) and forward it to OpenClaw. In OpenClaw, read tenant ID from request and attach to session/context. | Request to Control UI (or one API) shows correct `tenant_id` in OpenClaw logs and in one downstream call. |
| 1.2 | **Reject unauthenticated:** Ensure no agent/workload path is reachable without auth. Document that “orchestrator first” means all execution requests will later go through orchestrator. | Security review: no anonymous execution path. |
| 1.3 | **State backends — metadata:** Deploy Postgres (or use existing DB). Add schema for tenants, swarms, sandboxes, executor_pools (tables mirroring future CRDs). OpenClaw or a small service can read/write for now. | Tables exist; one write (e.g. “tenant registered”) and one read succeed. |
| 1.4 | **State backends — artifacts (optional for Phase 1):** Define how artifacts/checkpoints will be stored (object store or RWX volume). Add config/values for bucket or path; no executor integration yet. | Config present; optional upload script or test write succeeds. |

---

## Phase 2: CRDs and Operator (Desired State)

**Goal:** Kubernetes reflects desired state via Tenant, Swarm, Sandbox, ExecutorPool; an operator creates/updates K8s resources.

| Step | Action | Verification |
|------|--------|--------------|
| 2.1 | **CRD definitions:** Add CustomResourceDefinitions for Tenant, Swarm, Sandbox, ExecutorPool (in openclaw-helm or a separate `openclaw-crds` chart). Specs per Design.md §9. | `kubectl apply -f crds/` succeeds; `kubectl get tenant,swarm,sandbox,executorpool` shows resources. |
| 2.2 | **Operator scaffold:** Add an operator (Go or Python, or KubeBuilder/Operator SDK) that watches Tenant, Swarm, Sandbox, ExecutorPool. On create/update, reconcile to K8s resources (e.g. Namespace for Tenant; Sandbox → Pod). | Creating a Tenant CR creates a namespace; creating a Sandbox CR creates a Pod (standard runtime first). |
| 2.3 | **Sandbox → Pod mapping:** Operator creates one Pod per Sandbox CR. Pod spec: single container (OpenClaw gateway/executor) for now; no Kata yet. Use labels: `tenant`, `sandbox`, `agent-type`. | `kubectl apply -f sandbox-cr.yaml` creates a Pod with correct labels. |
| 2.4 | **ExecutorPool → replica count:** Operator creates or updates a Deployment (or similar) per ExecutorPool CR; replica count = desired executor count. For now, one Deployment per ExecutorPool in the tenant namespace. | Updating ExecutorPool.spec.replicas (or min/max) changes Deployment replica count. |

**Verification gate for Phase 2:** Create one Tenant, one Swarm, one Sandbox, one ExecutorPool via CRs; operator creates namespace + Pod(s); pods become Ready.

---

## Phase 3: Queue and Task Distribution

**Goal:** Orchestrator enqueues task units; executors pull work from a durable queue; at-least-once delivery.

| Step | Action | Verification |
|------|--------|--------------|
| 3.1 | **Queue deployment:** Deploy NATS (or Redis Streams / Kafka) via Helm or manifests. Configure stream or subject for task dispatch (e.g. per-tenant or per–agent-type). | Publish a test message; consume it from a second process. |
| 3.2 | **Task unit schema:** Define task message schema: tenant_id, swarm_id, agent_type, shard_id, task_id, payload, idempotency key. Document in protocol or API spec. | Schema doc exists; one example message serializes/deserializes. |
| 3.3 | **Orchestrator — enqueue:** Add an “orchestrator” component (new service or extension in OpenClaw gateway). On validated execution request, decompose into task units and publish to queue. | Send one execution request; corresponding task messages appear in queue (inspect via CLI or logs). |
| 3.4 | **Executor — pull:** In OpenClaw (executor mode) or a thin wrapper, subscribe to queue for its tenant/agent-type/shard; process one task, ack/nak. | One executor process pulls a task and logs completion; message is acked (or removed). |
| 3.5 | **Routing rule:** Orchestrator assigns task to agent type (and shard) per routing rules or config. | Task with type “email” lands in email agent-type stream/queue. |

**Verification gate for Phase 3:** End-to-end: one client request → orchestrator enqueues N tasks → executor(s) pull and process; no task lost (at least once).

---

## Phase 4: Sandbox Runtime — Kata + Firecracker, Init/Supervisor

**Goal:** Sandbox pods run with Kata Containers (Firecracker-backed); one init/supervisor process starts multiple OpenClaw executors inside the microVM.

| Step | Action | Verification |
|------|--------|--------------|
| 4.1 | **Kata + Firecracker on cluster:** Install Kata Containers with Firecracker runtime on worker nodes; create a RuntimeClass (e.g. `kata-firecracker`). | `kubectl get runtimeclass` shows class; a test Pod with `runtimeClassName: kata-firecracker` runs and `uname` shows guest kernel. |
| 4.2 | **Sandbox Pod uses Kata:** Operator sets `spec.runtimeClassName: kata-firecracker` on Sandbox Pods. No init/supervisor yet; single OpenClaw container. | Sandbox Pod runs in Kata; OpenClaw starts and can accept work. |
| 4.3 | **Init/Supervisor image:** Build a minimal init/supervisor that: starts N OpenClaw executor processes (N from env or file), restarts them on exit, sets up /var/openclaw layout. | Image runs in a test container; starts 2 OpenClaw processes; both visible in `ps`. |
| 4.4 | **Sandbox directory layout:** In sandbox Pod, provide volumes: `shared-readonly`, `shared-rw`, per-executor `work/<id>`, `log`. Mount into supervisor and executor containers. | Executors see `/var/openclaw/work/<id>`, `/var/openclaw/shared-ro`, `/var/openclaw/shared-rw`. |
| 4.5 | **One Pod = one Sandbox:** Sandbox Pod runs init/supervisor as main container (or init container that writes config) and executors as sidecars or children of supervisor. Document choice (single container with supervisor + children vs multi-container). | One Sandbox CR → one Pod; Pod runs multiple executor processes; each bound to one agent type + shard (config or env). |

**Verification gate for Phase 4:** Create Sandbox CR; Pod runs in Kata with Firecracker; supervisor starts 2+ executors with correct work dirs; executors pull from queue.

---

## Phase 5: Executor Pools, Scaling, and KEDA

**Goal:** ExecutorPool CR drives replica count; KEDA scales based on queue depth; scale to zero when idle.

| Step | Action | Verification |
|------|--------|--------------|
| 5.1 | **ExecutorPool CR → Deployment + KEDA:** Operator creates a Deployment (or similar) for each ExecutorPool and a KEDA ScaledObject (or HPA) that scales on queue depth (NATS stream lag or Redis list length). | Increase queue depth; replica count increases; drain queue; replicas scale down (to min or zero). |
| 5.2 | **Scale hierarchy:** Document and implement: scale executors inside existing sandbox up to max; then add sandboxes; then rely on cluster autoscaler for new nodes. Operator or scheduler creates new Sandbox CRs when pool needs more capacity. | At high load, new Sandbox CRs are created; new Pods run and join the pool. |
| 5.3 | **Shard assignment:** Each executor gets a shard ID (env or queue subscription). Ensure task routing sends tasks to the correct shard queue. | Executors for shard 1 only receive shard-1 tasks; no cross-shard delivery. |
| 5.4 | **Bounds and quotas:** Enforce min/max replicas per ExecutorPool and per-tenant sandbox/quota limits in operator or orchestrator. | Setting tenant quota to 2 sandboxes prevents third Sandbox from being created. |

**Verification gate for Phase 5:** Queue backlog triggers scale-up; replicas process work; scale-to-zero when queue empty (if enabled); quota prevents over-provisioning.

---

## Phase 6: Tool Proxy and Secrets Broker

**Goal:** Executors request tool access; broker checks policy, issues short-lived creds, logs access.

| Step | Action | Verification |
|------|--------|--------------|
| 6.1 | **Broker service:** Implement gateway-auth-proxy or a new “tool broker” service: HTTP API that accepts “request tool X for tenant T” with executor identity; checks policy; returns short-lived token or denies. | Executor calls broker; receives token when allowed; receives 403 when not allowed. |
| 6.2 | **Policy store:** Store per-tenant allowed tools and optional risk class. Broker reads policy before issuing. | Changing tenant policy to deny a tool causes next broker request to return 403. |
| 6.3 | **Audit logging:** Log every request, grant, and denial with tenant_id, executor_id, tool, timestamp, outcome. | Audit log contains entries for a grant and a denial. |
| 6.4 | **OpenClaw executor integration:** When OpenClaw executor needs a tool, call broker instead of using embedded credentials. | One tool call (e.g. email or browser) goes through broker and uses issued token. |

**Verification gate for Phase 6:** Executor requests tool access; broker grants or denies per policy; audit log is written; executor uses token for one external call.

---

## Phase 7: Durable State, Checkpoints, Resume

**Goal:** Durable state outside sandbox; cold resume from checkpoint; optional warm resume from snapshot.

| Step | Action | Verification |
|------|--------|--------------|
| 7.1 | **Artifacts and checkpoints to durable storage:** Executors write artifacts and checkpoints to object store or RWX volume (tenant-scoped path). No longer only local to sandbox. | After executor run, artifact is visible in object store (or shared FS) under tenant path. |
| 7.2 | **Cold resume:** On new sandbox start, load tenant durable state (metadata, last checkpoint); executor reconstructs context and resumes. | Stop sandbox; create new sandbox for same tenant; executor resumes from checkpoint and continues work. |
| 7.3 | **Idle timeout and scale-to-zero:** When tenant idle exceeds timeout, scale ExecutorPools to zero; preserve durable state. On new work, orchestrator triggers scale-up and cold start. | Idle tenant scales to zero; new task triggers scale-up; new executor loads state and runs. |
| 7.4 | **Warm resume (optional):** If Firecracker snapshot is configured, snapshot sandbox before scale-to-zero; on resume, restore from snapshot and reinit uniqueness-sensitive data. | (Should Have) One warm-resume path: restore from snapshot; verify process state and then reinit tokens/IDs. |

**Verification gate for Phase 7:** Tenant runs task, checkpoints; sandbox removed; new sandbox starts and cold-resumes from checkpoint. Optionally warm-resume from snapshot.

---

## Phase 8: Tenant Isolation and Policy

**Goal:** Network, storage, and quota isolation; high-risk workload separation.

| Step | Action | Verification |
|------|--------|--------------|
| 8.1 | **Network policy:** Per-tenant deny east-west by default; allow only orchestrator/queue/broker/state endpoints. Apply NetworkPolicy in tenant namespaces. | Tenant A pod cannot reach Tenant B pod; can reach queue and broker. |
| 8.2 | **Storage isolation:** Tenant-scoped PVCs or object-store prefixes; no cross-tenant access. | Tenant A cannot read Tenant B’s artifacts or metadata. |
| 8.3 | **High-risk sandbox separation:** Scheduler (or operator) places high-risk agent types (e.g. shell, browser) in separate Sandbox CRs; same tenant, different sandboxes. | Swarm with email + shell creates two Sandboxes; shell in dedicated sandbox. |
| 8.4 | **Quota enforcement:** Orchestrator and operator enforce per-tenant sandbox count, CPU, memory, storage. Reject or queue when over quota. | Request that would exceed tenant quota is rejected with clear condition. |

**Verification gate for Phase 8:** Two tenants; no cross-tenant access; high-risk workload in separate sandbox; over-quota request rejected.

---

## Phase 9: Observability and Operations

**Goal:** Structured logs, metrics, tenant-scoped tracing, health/readiness, operator visibility.

| Step | Action | Verification |
|------|--------|--------------|
| 9.1 | **Structured logging:** Control plane and executors emit structured logs (JSON) with tenant_id, swarm_id, sandbox_id, task_id where applicable. | Log pipeline or grep shows tenant_id and task_id for a request. |
| 9.2 | **Metrics:** Expose metrics for queue depth, task latency, executor count, sandbox count, broker grants/denials. | Prometheus or equivalent scrapes metrics; one dashboard shows queue depth and executor count. |
| 9.3 | **Tracing:** Add correlation ID or trace ID from gateway through orchestrator to executor and broker. | One request has same trace_id in gateway, orchestrator, and executor logs. |
| 9.4 | **Health and readiness:** All control-plane components and executor pods expose /health and /ready; K8s probes configured. | Killing a component causes readiness to fail and load balancer to stop sending traffic. |
| 9.5 | **Operator visibility:** Document or UI for tenant usage, quota consumption, failure conditions. | Operator can list tenants and see sandbox count and quota usage. |

**Verification gate for Phase 9:** Logs, metrics, and traces available; probes in place; basic operator view of tenants and usage.

---

## Dependency Overview

```
Phase 0 (Foundation)
    → Phase 1 (Gateway, Tenant, State)
        → Phase 2 (CRDs, Operator)
            → Phase 3 (Queue, Orchestrator, Executor pull)
                → Phase 4 (Kata, Firecracker, Init/Supervisor)
                    → Phase 5 (KEDA, ExecutorPool scaling)
Phase 1, 3
    → Phase 6 (Tool Broker)
Phase 1, 4, 7 (state backends, sandbox, storage)
    → Phase 7 (Durable state, cold/warm resume)
Phase 2, 4, 5
    → Phase 8 (Tenant isolation, policy)
Phase 1–8
    → Phase 9 (Observability)
```

---

## Where Changes Live

| Area | Where | Notes |
|------|--------|--------|
| **openclaw** | Tenant ID in context, executor queue consumer, broker client, checkpoint write to durable store | Same Dockerfile; new modes or config. |
| **openclaw-helm** | Values for queue, state, broker; CRD manifests; operator deployment; KEDA ScaledObjects; Kata RuntimeClass; network policies | Most new YAML in Helm or subcharts. |
| **gateway-nginx** | Tenant header/claim forwarding | Config change only. |
| **gateway-auth-proxy** | Implement as Tool Proxy / Secrets Broker (or separate broker service) | New implementation. |
| **New components** | Orchestrator, Init/Supervisor, Operator | New repos or folders; new Dockerfiles. |
| **Dockerfiles** | OpenClaw, gateway-nginx | Unchanged for image content; optional multi-stage for smaller executor image. |
| **gateway-auth-proxy** | Currently placeholder | Implement in Phase 6 as broker. |

---

## Suggested Order of Implementation (Summary)

1. **Phase 0** — Docs and tenant ID in one path.  
2. **Phase 1** — Tenant at edge, state backends.  
3. **Phase 2** — CRDs and operator (Sandbox → Pod, ExecutorPool → replicas).  
4. **Phase 3** — Queue + orchestrator enqueue + executor pull.  
5. **Phase 4** — Kata/Firecracker for Sandbox pods; init/supervisor and directory layout.  
6. **Phase 5** — KEDA and scale hierarchy; shard assignment; quotas.  
7. **Phase 6** — Tool broker and audit.  
8. **Phase 7** — Durable state, cold resume, scale-to-zero, optional warm resume.  
9. **Phase 8** — Network/storage isolation, high-risk separation, quota enforcement.  
10. **Phase 9** — Logs, metrics, tracing, health, operator visibility.

Each phase ends with a **verification gate** so you can stop and validate before moving on. This gets you from the current single-gateway + optional nginx/OAuth deployment to the full design in Requirements.md and FullDiagram.png with Firecracker-backed sandboxes, CRD-driven control plane, queue-based distribution, and tool broker.
