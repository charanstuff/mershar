Full System Requirements
1. Scope

The system shall provide a secure, multi-tenant platform for running OpenClaw-based agent workloads in isolated tenant sandboxes. Each tenant may run one or more agent swarms composed of multiple agent types and multiple parallel executors. The platform shall support strong isolation, elastic scaling, durable state, and controlled tool access.

2. Definitions

Tenant: A logically isolated customer/account boundary.

Swarm: A tenant-scoped logical workload composed of one or more agent types.

Agent Type: A functional class of agent, such as email, notes, browser, or shell.

Executor: A single running OpenClaw process assigned to a shard of work.

Sandbox: An isolated execution environment backed by a Firecracker microVM.

ExecutorPool: A scalable group of executors for a single agent type.

Shard: A partition of tenant work assigned to one executor.

Cold Resume: Restart from durable state only.

Warm Resume: Restore using a microVM snapshot.

3. Functional Requirements
3.1 Tenant Identity and Isolation

Ubiquitous: The system shall maintain a unique tenant identity for every incoming request.

Event-driven: When a new tenant is registered, the system shall create tenant-scoped configuration, quota, policy, and storage metadata.

Ubiquitous: The system shall isolate tenant workloads from workloads belonging to other tenants.

Ubiquitous: The system shall isolate tenant secrets, credentials, and tokens from those of all other tenants.

Ubiquitous: The system shall isolate tenant durable state, including metadata, artifacts, and memory files, from the durable state of all other tenants.

State-driven: While a tenant sandbox is running, the system shall prevent guest workloads from directly accessing host namespaces, host filesystems, and host network interfaces except through explicitly permitted virtualized interfaces.

Ubiquitous: The system shall enforce per-tenant resource quotas for CPU, memory, storage, and concurrent sandbox count.

Complex: Where a tenant is assigned regulatory, premium, or high-risk isolation requirements, the system shall support stricter placement and isolation policies for that tenant than for standard tenants.

3.2 Request Ingress and Routing

Event-driven: When a client submits a request, the system shall authenticate the caller before scheduling any agent workload.

Event-driven: When a request is authenticated, the system shall resolve the associated tenant identity and apply tenant-specific policies.

Ubiquitous: The system shall route all agent-execution requests through the orchestrator before any request reaches a sandbox.

Event-driven: When a tenant is inactive and receives new work, the orchestrator shall determine whether the tenant requires cold start or warm restore.

Event-driven: When a request exceeds tenant quota or violates policy, the system shall reject the request with a tenant-scoped error response.

Ubiquitous: The system shall support idempotent request handling for retried client submissions.

3.3 Swarm Creation and Work Decomposition

Event-driven: When a tenant triggers an agent swarm, the system shall create or update a tenant-scoped swarm record.

Event-driven: When a swarm request contains multiple independent work items, the system shall decompose the request into separately schedulable task units.

Event-driven: When decomposing a swarm request, the system shall assign task units to agent types according to routing rules or configuration.

Ubiquitous: The system shall support multiple agent types within the same tenant swarm.

Ubiquitous: The system shall support multiple shards per agent type.

Complex: When a swarm contains both low-risk and high-risk agent types, the system shall be able to separate them into different sandboxes while preserving tenant-level coordination.

Ubiquitous: The system shall record scheduling metadata for every task unit, including tenant, swarm, agent type, shard, and assigned executor.

3.4 Scheduling and Placement

Event-driven: When a task unit is created, the scheduler shall assign it to an eligible executor pool or create new capacity if none is available.

Ubiquitous: The scheduler shall consider tenant quota, sandbox capacity, workload class, and placement policy when assigning work.

Event-driven: When existing sandbox headroom is sufficient, the scheduler shall prefer placing additional executors into an existing sandbox before creating a new sandbox.

Event-driven: When executor demand exceeds the configured capacity of a sandbox, the scheduler shall provision an additional sandbox for the tenant.

Complex: When a workload is classified as high-risk, the scheduler shall place that workload only into sandboxes approved for that risk class.

State-driven: While cluster capacity is constrained, the scheduler shall apply fairness rules so that no single tenant can monopolize available capacity.

Ubiquitous: The scheduler shall support affinity and anti-affinity placement rules for sandboxes.

3.5 Sandbox Provisioning and Execution

Event-driven: When a sandbox is requested, the system shall provision an isolated execution environment backed by a Firecracker microVM via the configured runtime.

Ubiquitous: Each sandbox shall run with explicitly assigned CPU and memory limits.

Ubiquitous: Each sandbox shall run one or more OpenClaw executors under a supervisor or equivalent init process.

Ubiquitous: The system shall support multiple sandboxes per tenant.

State-driven: While a sandbox is running, the system shall health-check the sandbox and the executors within it.

Event-driven: When an executor process exits unexpectedly, the system shall restart the executor or replace the sandbox according to configured restart policy.

Complex: When a sandbox enters an unrecoverable state, the system shall terminate the sandbox, mark in-flight work appropriately, and reschedule recoverable tasks.

3.6 Executor Management

Event-driven: When an executor pool is scaled up, the system shall create the required number of executor instances for the target agent type.

Ubiquitous: Each executor shall be bound to exactly one agent type and one shard assignment at a time.

Ubiquitous: The system shall support independent scaling of executor pools per agent type.

State-driven: While multiple executors run in the same sandbox, the system shall provide per-executor working directories.

State-driven: While executors share writable state in the same sandbox, the system shall enforce concurrency protection for shared writable resources.

Ubiquitous: The system shall support graceful executor shutdown for scale-down and maintenance.

Event-driven: When an executor is terminated during scale-down, the system shall checkpoint or requeue unfinished work before terminating it, where supported.

3.7 Queueing and Work Distribution

Ubiquitous: The system shall use durable or recoverable queueing for task dispatch between the orchestrator and executor pools.

Event-driven: When new task units are created, the system shall enqueue them for the appropriate tenant and agent type.

Ubiquitous: The queueing layer shall preserve task ownership metadata, including tenant, swarm, agent type, and shard.

Event-driven: When an executor becomes available, it shall pull or receive only tasks for which it is authorized.

State-driven: While queue depth exceeds configured thresholds, the system shall scale executor pools according to autoscaling policy.

Event-driven: When task processing fails, the system shall support retry, dead-lettering, or operator intervention according to configured retry policy.

Ubiquitous: The system shall support at-least-once delivery semantics unless a stricter delivery guarantee is explicitly configured.

3.8 State, Persistence, and Checkpointing

Ubiquitous: The system shall persist durable tenant state outside the sandbox boundary.

Ubiquitous: Durable state shall include at minimum artifacts, task metadata, checkpoints, logs, and tenant memory/state files.

Ubiquitous: The system shall distinguish between durable state and in-memory execution state.

Event-driven: When an executor reaches a checkpoint boundary, the system shall persist checkpointable state to durable storage.

State-driven: While a tenant is inactive beyond the configured idle timeout, the system may terminate sandbox compute while preserving durable state.

Event-driven: When a previously idle tenant receives new work, the system shall restore execution using cold resume or warm resume according to tenant or workload policy.

Complex: When warm resume mode is enabled, the system shall restore only from compatible snapshots and shall reinitialize non-clonable or uniqueness-sensitive runtime data before processing new work.

Ubiquitous: The system shall support per-tenant storage isolation within all persistent backends.

3.9 Shared State and Inter-Executor Coordination

Ubiquitous: The system shall support controlled shared state among executors belonging to the same tenant.

State-driven: While multiple executors access shared writable state, the system shall prevent data corruption through locking, atomic writes, version checks, or equivalent concurrency controls.

Ubiquitous: The system shall support shared read-only assets that may be mounted or exposed to multiple executors in the same sandbox.

Ubiquitous: The system shall support per-executor private working state separate from shared writable state.

Event-driven: When an executor publishes a shared artifact, the system shall make that artifact discoverable to authorized executors within the same tenant.

Complex: When shared state becomes unavailable or inconsistent, the system shall degrade gracefully by retrying, rebuilding state, or isolating affected work units.

3.10 Tool Access and Secrets Brokering

Ubiquitous: The system shall broker tool access through a controlled intermediary rather than embedding broad credentials directly in executors.

Event-driven: When an executor requests access to a tool, the broker shall evaluate the request against tenant policy, workload policy, and tool allowlists.

Event-driven: When access is permitted, the broker shall issue credentials or tokens scoped to the tenant, the tool, and a bounded lifetime.

Event-driven: When access is denied, the broker shall reject the request and record the denial.

Ubiquitous: The system shall log all tool access requests, grants, denials, and credential issuance events.

Complex: When a tool supports narrower scopes than the requested scope, the broker shall issue the narrowest scope sufficient for the requested operation.

3.11 Network Controls

Ubiquitous: The system shall enforce tenant-scoped ingress and egress policy for sandbox workloads.

Ubiquitous: The system shall deny sandbox-to-sandbox network access by default unless explicitly permitted by policy.

State-driven: While a sandbox executes workloads, the system shall allow only approved outbound network destinations for that workload class.

Complex: When a workload is classified as high-risk, the system shall apply stricter egress controls than those used for low-risk workloads.

Ubiquitous: The system shall support auditability of network policy decisions for sandboxed workloads.

3.12 Autoscaling

Event-driven: When queue depth or event backlog exceeds configured thresholds, the system shall scale the corresponding executor pool up.

State-driven: While no work is pending for an executor pool and scale-to-zero is enabled, the system may scale that pool to zero.

Event-driven: When sandbox capacity is insufficient for the desired executor count, the system shall provision additional sandboxes.

State-driven: While sandbox pods remain unschedulable, the system shall request additional node capacity through the configured node autoscaler.

Ubiquitous: The system shall enforce minimum and maximum scaling bounds for executor pools and sandbox counts.

Complex: When autoscaling would exceed tenant quota, the system shall stop scaling for that tenant and surface a quota-related condition.

3.13 Fault Tolerance and Recovery

Event-driven: When an executor fails, the system shall mark the task state and recover the task according to retry policy.

Event-driven: When a sandbox fails, the system shall replace the sandbox and reschedule recoverable work.

State-driven: While a dependent service such as the queue, broker, or persistent state backend is degraded, the system shall prevent silent task loss.

Ubiquitous: The system shall preserve audit trails and failure metadata for all failed tasks and failed sandbox launches.

Complex: When a tenant repeatedly triggers crash loops or policy violations, the system shall support tenant-specific throttling or suspension.

3.14 Observability and Audit

Ubiquitous: The system shall emit structured logs for control-plane actions, scheduling events, sandbox lifecycle events, executor lifecycle events, and tool access events.

Ubiquitous: The system shall emit metrics for queue depth, task latency, executor count, sandbox count, startup failures, retry rates, and resource utilization.

Ubiquitous: The system shall support tenant-scoped tracing or correlation IDs across request, scheduling, execution, and tool access paths.

Event-driven: When a security-sensitive event occurs, the system shall emit an auditable security event record.

Ubiquitous: Audit records shall include tenant identity, actor identity where available, time, action, and outcome.

3.15 Administration and Policy Management

Ubiquitous: The system shall allow operators to define per-tenant quotas, allowed tools, idle timeouts, resume mode, and risk-class policies.

Ubiquitous: The system shall allow operators to define global policies for scaling, retries, retention, and security controls.

Event-driven: When a policy is updated, the system shall apply the new policy to future work and to running workloads where safe and supported.

Complex: When a policy change conflicts with running workloads, the system shall either defer application, restart affected workloads, or reject the change with an explanatory condition.

4. Security Requirements
4.1 Authentication and Authorization

Ubiquitous: All external API access shall require authenticated identity.

Ubiquitous: All control-plane actions shall require authorization checks.

Ubiquitous: All tool access shall require tenant-scoped authorization.

Ubiquitous: The system shall support least-privilege permissions for operators, services, and workloads.

4.2 Isolation

Ubiquitous: The system shall enforce tenant isolation at identity, compute, network, and storage layers.

Ubiquitous: The system shall ensure that sandbox workloads cannot read or write host-mounted paths unless explicitly required and approved.

Ubiquitous: The system shall prevent direct sharing of secrets between sandboxes.

Complex: Where stricter security tiers are configured, the system shall support dedicated node pools or dedicated placement domains for selected tenants or workloads.

4.3 Secrets and Credentials

Ubiquitous: Secrets shall be encrypted at rest and protected in transit.

Event-driven: When short-lived credentials expire, the system shall revoke or refuse further use of those credentials.

Ubiquitous: The system shall rotate broker-issued credentials or tokens according to configured lifetime policies.

4.4 Auditability

Ubiquitous: All privileged actions shall be auditable.

Ubiquitous: The system shall retain audit logs for a configurable retention period.

Complex: When audit log delivery fails, the system shall buffer, retry, or surface an operator alert rather than silently dropping logs.

5. Performance Requirements

These should be targets, not hard absolutes.

Ubiquitous: The system shall support concurrent execution of multiple tenants.

Ubiquitous: The system shall support concurrent execution of multiple sandboxes per tenant.

Ubiquitous: The system shall support parallel executor processing within the limits of assigned sandbox resources.

Ubiquitous: The system shall expose configurable SLO targets for request admission latency, executor start latency, task queue latency, and task completion latency.

Event-driven: When warm resume is enabled and a compatible snapshot exists, the system shall prefer warm restore over cold start for latency-sensitive workloads.

Ubiquitous: The system shall support backpressure mechanisms when incoming workload exceeds safe processing capacity.

6. Reliability Requirements

Ubiquitous: The system shall avoid single points of failure in the control plane where feasible.

Ubiquitous: The system shall persist enough metadata to recover from control-plane restarts without orphaning tenant state.

Event-driven: When the orchestrator restarts, the system shall reconcile desired state with actual state.

Event-driven: When the queueing system restarts, the system shall restore pending task visibility according to queue durability guarantees.

Ubiquitous: The system shall support rolling upgrades of control-plane services with minimal disruption.

7. Scalability Requirements

Ubiquitous: The system shall support horizontal scaling of control-plane services.

Ubiquitous: The system shall support horizontal scaling of executor pools independently per agent type.

Ubiquitous: The system shall support horizontal scaling of sandboxes for a single tenant.

Ubiquitous: The system shall support multiple tenants sharing the same cluster while respecting isolation and quota rules.

Complex: When cluster-level saturation is approached, the system shall enforce fairness and preserve service for existing tenants according to policy.

8. Data Management Requirements

Ubiquitous: The system shall store tenant data in a manner that preserves tenant ownership and isolation.

Ubiquitous: The system shall support configurable retention and deletion policies for tenant artifacts, logs, and checkpoints.

Event-driven: When a tenant is deleted or offboarded, the system shall delete or archive tenant data according to retention policy and compliance requirements.

Ubiquitous: The system shall support backup and recovery procedures for persistent metadata and durable state.

9. Operational Requirements

Ubiquitous: The system shall expose health and readiness indicators for control-plane services, sandboxes, and executor pools.

Ubiquitous: The system shall support operator visibility into tenant usage, quota consumption, and failure conditions.

Event-driven: When a tenant exceeds quota, the system shall surface a clear condition to the tenant and to operators.

Event-driven: When cluster capacity becomes insufficient, the system shall surface an operator-visible capacity alert.

Ubiquitous: The system shall support manual pause, resume, drain, or disable actions for tenants, swarms, sandboxes, and executor pools.

10. Compliance and Governance Requirements

Ubiquitous: The system shall support policy-driven retention, access control, and audit collection.

Ubiquitous: The system shall support tenant-level configuration of residency, retention, or isolation class where required by policy.

Complex: When tenant governance policy conflicts with platform defaults, the system shall apply the stricter effective control or reject unsupported configuration.

11. Suggested Acceptance Criteria

These are practical top-level checks.

Tenant Isolation

Tenant A cannot access Tenant B’s files, logs, secrets, queues, or executors.

Tenant-specific quotas are enforced.

High-risk workloads can be separated into dedicated sandboxes.

Scaling

A queue surge increases executor count.

When sandbox limits are hit, a new sandbox is created.

When pods are unschedulable, node autoscaling is triggered.

Idle workloads scale to zero when enabled.

Recovery

Executor crash causes restart or task retry.

Sandbox crash causes sandbox replacement and task recovery.

Cold resume restores durable state.

Warm resume restores snapshot-backed execution where enabled.

Security

Tool access is denied without policy approval.

Short-lived credentials expire correctly.

Network egress rules are enforced.

Audit logs exist for access grants, denials, and privileged actions.

12. Recommended Requirement Priorities
Must Have

Tenant isolation

Sandbox provisioning

Executor pools

Queue-based work distribution

Durable state

Tool broker

Autoscaling

Audit logging

Should Have

Warm resume

High-risk workload isolation classes

Fairness controls

Advanced placement policies

Manual pause/drain controls

Nice to Have

Dedicated premium tenancy modes

Snapshot tiering by tenant class

Predictive scaling

Cost-aware placement