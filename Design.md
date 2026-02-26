Secure Multi-Tenant OpenClaw Infrastructure v2

This version keeps your original intent—strong tenant isolation, parallel agent execution, and scale-to-zero—but aligns it with how Firecracker, Kata, Kubernetes, and KEDA actually work. Firecracker runs in user space on the host and uses Linux KVM to create microVMs; Kata can use Firecracker as a hypervisor-backed runtime for Kubernetes workloads.

1) System Requirements in EARS
Security and Multi-Tenancy

Event-driven: When a new tenant sandbox is requested, the system shall provision an isolated execution environment backed by a Firecracker microVM.

State-driven: While a tenant sandbox is running, the system shall prevent guest workloads from accessing host namespaces, host filesystems, and host network interfaces except through explicitly permitted virtualized interfaces.

Ubiquitous: The system shall enforce per-tenant identity, network, storage, and secret isolation for all workloads.

Ubiquitous: The system shall run tenant executors with least-privilege credentials scoped to the tenant and the enabled tool set.

Complex: Where a tenant workload is classified as high-risk (for example shell, browser automation, or external account access), the system shall schedule that workload into a dedicated sandbox separate from lower-risk workloads belonging to the same tenant.

Firecracker’s model is a VM boundary with a minimal device model, plus a “jailer” process for added isolation, while Kata provides a dedicated guest kernel boundary for the workload.

Parallelism

Event-driven: When a tenant triggers an agent swarm, the system shall launch multiple OpenClaw executors concurrently across one or more tenant sandboxes.

State-driven: While multiple executors are running in the same sandbox, the system shall provide controlled shared-state access with per-executor working directories and concurrency protection.

Ubiquitous: The system shall support independent scaling of executor count per agent type.

Complex: When a swarm contains multiple agent types, the system shall be able to place those agent types into separate sandboxes while preserving tenant-level coordination.

KEDA can scale workloads based on event sources, and each replica processes work in a distributed manner, which fits this executor model well.

Scalability

Event-driven: When executor demand exceeds the configured capacity of a tenant sandbox, the system shall provision additional tenant sandboxes and distribute work across them.

State-driven: While workload pods remain unschedulable or queue depth exceeds configured thresholds, the system shall request additional cluster node capacity through the configured node autoscaler.

Ubiquitous: The system shall enforce per-tenant resource quotas for CPU, memory, storage, and concurrent sandboxes.

Complex: When multiple tenants contend for cluster capacity, the system shall apply fairness controls so that one tenant cannot consume all newly provisioned capacity.

Kubernetes node autoscaling is driven primarily by unschedulable Pods, not a simple node-utilization threshold.

Lifecycle and Persistence

State-driven: While a tenant is inactive beyond the configured idle timeout, the system may scale that tenant’s executors to zero while preserving durable state.

Event-driven: When a previously idle tenant receives new work, the system shall restore execution by either cold-starting from durable state or restoring from a supported VM snapshot, depending on the configured resume mode.

Ubiquitous: The system shall distinguish between durable artifact state and in-memory execution state.

Complex: When warm-resume mode is enabled, the system shall restore only from compatible snapshots and shall reinitialize any non-clonable or uniqueness-sensitive runtime data before accepting new work.

KEDA supports scaling workloads to zero when no messages are pending and reactivating them when events arrive. Firecracker also supports snapshot-based resume, which is the right mechanism for restoring in-memory execution state rather than relying on a filesystem mount alone.

2) Architecture Overview
Core Stack

Kubernetes for orchestration

Kata Containers RuntimeClass for VM-backed pods

Firecracker as the microVM hypervisor

Envoy as edge gateway

KEDA for event-driven workload scale-up / scale-to-zero

Cluster Autoscaler or Karpenter for node capacity expansion

Kata explicitly supports Firecracker among its supported hypervisors, and KEDA is built to drive event-based workload scaling.

3) Control Plane

The control plane manages identity, policy, scheduling, and lifecycle. It does not execute agent code.

Components

API Gateway (Envoy)
Terminates TLS, authenticates the caller, resolves Tenant ID, and forwards requests to the orchestrator.

Tenant Orchestrator
Validates quotas, classifies requested work, decides whether to wake an idle tenant, and converts user requests into internal task units.

Scheduler / Placement Service
Maps task units onto one or more tenant sandboxes based on:

tenant quota

workload sensitivity

current queue depth

sandbox capacity

cold vs warm resume mode

Custom Resources

Tenant

Swarm

Sandbox

ExecutorPool

A CRD-driven model is a good fit for Kubernetes because the platform manages desired state while your operator implements the higher-level lifecycle. Kubernetes is built around this control loop pattern.

Recommended Control-Plane Rule

Do not route edge traffic directly to a tenant runtime.
Always route through the orchestrator first so it can:

enforce authz

check policy

wake scaled-to-zero sandboxes

fan out tasks

reject excess load cleanly

4) Compute Plane

This is where executor workloads run.

Runtime Model

Each Sandbox is implemented as a Kubernetes pod scheduled with a Kata RuntimeClass configured to launch a Firecracker-backed microVM.

Inside the microVM:

a minimal guest OS boots

a lightweight init process starts

one or more OpenClaw executors run

Kata provides VM-backed workload isolation, and Firecracker is designed for fast startup and high density with low overhead. Firecracker’s documentation states startup can initiate userspace/application code in as little as 125 ms and that each microVM has less than 5 MiB of overhead, but those are platform capabilities, not guaranteed end-to-end application readiness numbers.

Sandbox Placement Rules

A sandbox is the primary execution boundary.

Recommended default:

one tenant may have multiple sandboxes

one sandbox may host one or more executors

high-risk tools get separate sandboxes

This reduces intra-tenant blast radius while still preserving tenant ownership.

Resource Controls

Per sandbox:

fixed vCPU allocation

fixed memory allocation

optional I/O caps

per-sandbox network policy

per-sandbox egress allowlist

Firecracker supports built-in rate limiters for network and storage, which is useful for limiting per-sandbox abuse and smoothing resource sharing.

5) Tenant Sandbox Design

This replaces the “all agents share one giant writable directory” model with something safer.

Inside a Sandbox

Init / Supervisor
A lightweight supervisor starts the configured executor set and handles restarts.

Executors
Each executor is a single OpenClaw process bound to:

one agent type

one shard of work

one scoped credential set

Directory Layout

/var/openclaw/work/<executor-id> → private per-executor working directory

/var/openclaw/shared-readonly → shared read-only prompt/tool assets

/var/openclaw/shared-rw → controlled shared artifacts

/var/openclaw/log → structured execution logs

Coordination Model

Prefer:

queue-based coordination

append-only event logs

structured state records

Use shared RW filesystem only for:

artifacts

checkpoint files

explicitly shared outputs

If multiple executors write into shared RW storage, require:

file locking

optimistic concurrency controls

atomic rename/write patterns

This avoids the race-condition and corruption issues that come with many processes freely mutating the same state.

Local Communication

Executors in the same sandbox may communicate via:

loopback HTTP

Unix sockets

local queue sidecar

That keeps local chatter inside the microVM boundary.

6) State Model

The most important correction: filesystem persistence is not the same as execution-state persistence.

Durable State

Persist outside the microVM:

artifacts

user memory files

tool outputs

checkpoints

execution metadata

Backends can be:

RWX network filesystem

object storage

database-backed state store

Execution State

There are two resume modes:

Cold Resume

new sandbox boots

durable files are remounted/reloaded

executors reconstruct context from checkpoints

Warm Resume

sandbox is restored from a Firecracker snapshot

memory/process state resumes

uniqueness-sensitive values are refreshed as needed

Firecracker snapshot support exists specifically for loading a microVM later and resuming the original guest workload, which is the right fit for warm resume.

Recommended Policy

Default to cold resume for simplicity.
Use warm resume only for premium or latency-sensitive tenants because snapshot management is operationally heavier.

7) Autoscaling Design
Workload Scaling

Use KEDA to scale ExecutorPool resources based on:

queue depth

pending tasks

inbox size

webhook event count

scheduler backlog

KEDA can scale to zero when no work is pending and activate the workload when events arrive.

Node Scaling

Use Cluster Autoscaler or Karpenter for worker nodes.

Trigger node growth when:

new sandbox pods are unschedulable

placement cannot satisfy CPU / memory / topology rules

reserved tenant headroom drops below policy

Kubernetes documents node autoscaling as responding to Pods that cannot be scheduled onto current nodes.

Scaling Hierarchy

Increase executor count inside an existing sandbox if headroom exists

Add another sandbox for the tenant if sandbox-level limits are reached

Add more cluster nodes if sandbox pods become unschedulable

That gives you predictable scale-out without prematurely growing the cluster.

8) Security Controls
Identity and Secrets

Never bake broad credentials into sandbox images.

Use a Secrets Broker / Tool Proxy:

executors request access to a tool

broker verifies policy

broker issues short-lived scoped tokens

broker logs access

Network Policy

Per tenant:

deny east-west traffic by default

allow only orchestrator-approved ingress

restrict egress to approved domains/APIs

segment tenant traffic at the Kubernetes network layer

Isolation Policy

Per sandbox:

dedicated guest kernel boundary

no host path mounts

no host networking

minimal device exposure

read-only rootfs where feasible

Kata’s value proposition is exactly this additional VM-backed isolation layer using hardware virtualization.

9) Suggested CRDs
Tenant

Defines:

identity

quotas

allowed tools

default resume mode

idle timeout

network policy profile

Swarm

Defines:

requested agent types

workload class

task decomposition policy

concurrency target

Sandbox

Defines:

tenant owner

runtime class

vCPU / memory

risk class

resume mode

attached storage profile

ExecutorPool

Defines:

agent type

shard count

min/max executors

KEDA trigger config

queue binding

This is a cleaner model than overloading “replica” to mean multiple different things.

10) Operational Targets

Use these as realistic targets instead of hard claims:

Cold start: “best-effort low-latency startup; target under a few seconds end-to-end for standard tenants”

Warm resume: “best-effort faster-than-cold restore when snapshot mode is enabled”

Isolation: “strong VM-backed workload isolation with tenant policy enforcement”

Fairness: “per-tenant quotas and queue controls prevent uncontrolled resource monopolization”

Firecracker supports fast startup, but full application readiness depends on guest image size, runtime init, storage attach, and OpenClaw startup, so avoid hardcoding “~200 ms” unless you benchmark your own stack.

11) Concise Reference Flow

User request hits Envoy

Orchestrator authenticates and resolves tenant

Orchestrator decomposes work into agent tasks

Scheduler assigns tasks to one or more ExecutorPools

KEDA scales pools based on queued work

Kubernetes schedules Sandbox pods via Kata RuntimeClass

Kata launches Firecracker-backed microVMs

Executors run OpenClaw inside those sandboxes

State is checkpointed to durable storage

Idle pools scale to zero; warm tenants may snapshot before shutdown