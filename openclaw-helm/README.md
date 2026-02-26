# OpenClaw Helm Chart

[![Helm 3](https://img.shields.io/badge/Helm-3.0+-0f1689?logo=helm&logoColor=white)](https://helm.sh/)
[![Kubernetes 1.19+](https://img.shields.io/badge/Kubernetes-1.19+-326ce5?logo=kubernetes&logoColor=white)](https://kubernetes.io/)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

A Helm chart for deploying [OpenClaw](https://openclaw.ai/) — an open-source AI personal assistant — to Kubernetes.

[Documentation](https://openclaw.ai/docs) | [Issues](https://github.com/openclaw/openclaw-helm/issues) | [Discussions](https://github.com/openclaw/openclaw-helm/discussions)

---

## Quick Start

```bash
helm repo add openclaw https://chrisbattarbee.github.io/openclaw-helm
helm repo update
helm install openclaw openclaw/openclaw --set credentials.anthropicApiKey=sk-ant-xxx
```

This installs OpenClaw version **2026.2.17** by default. To use a different version, set `image.tag`.

---

## Installation

### Prerequisites

- Kubernetes 1.19+
- Helm 3.0+
- An API key from a supported LLM provider (Anthropic, OpenAI, etc.)

### From Helm Repository (Recommended)

```bash
# Add the repository
helm repo add openclaw https://chrisbattarbee.github.io/openclaw-helm
helm repo update

# Install the chart
helm install openclaw openclaw/openclaw --set credentials.anthropicApiKey=sk-ant-xxx
```

<details>
<summary><b>Install from Local Clone (Development)</b></summary>

```bash
git clone https://github.com/Chrisbattarbee/openclaw-helm.git
cd openclaw-helm
helm install openclaw ./charts/openclaw --set credentials.anthropicApiKey=sk-ant-xxx
```

</details>

<details>
<summary><b>Using an Existing Secret</b></summary>

Create a secret with your API keys:

```bash
kubectl create secret generic openclaw-credentials \
  --from-literal=ANTHROPIC_API_KEY=sk-ant-xxx \
  --from-literal=OPENAI_API_KEY=sk-xxx
```

Then install the chart:

```bash
helm install openclaw openclaw/openclaw --set credentials.existingSecret=openclaw-credentials
```

</details>

<details>
<summary><b>With Custom Values</b></summary>

```bash
helm install openclaw openclaw/openclaw -f my-values.yaml
```

</details>

---

## Configuration

### Key Parameters

| Parameter                                  | Description                           | Default                              |
| ------------------------------------------ | ------------------------------------- | ------------------------------------ |
| `image.repository`                         | Container image repository            | `ghcr.io/openclaw/openclaw`          |
| `image.tag`                                | Container image tag                   | `2026.2.17`                          |
| `openclaw.agents.defaults.model`           | Primary model (provider/model format) | `anthropic/claude-sonnet-4-20250514` |
| `openclaw.agents.defaults.timeoutSeconds`  | Agent timeout in seconds              | `600`                                |
| `openclaw.agents.defaults.thinkingDefault` | Thinking mode (low/high/off)          | `low`                                |
| `openclaw.timezone`                        | Timezone environment variable         | `UTC`                                |
| `openclaw.bind`                            | Bind mode (localhost/lan)             | `localhost`                          |
| `credentials.anthropicApiKey`              | Anthropic API key                     | `""`                                 |
| `credentials.existingSecret`               | Use existing secret                   | `""`                                 |
| `chromium.enabled`                         | Enable browser automation             | `true`                               |
| `persistence.enabled`                      | Enable persistent storage             | `true`                               |
| `ingress.enabled`                          | Enable ingress                        | `false`                              |

<details>
<summary><b>Full Configuration Reference</b></summary>

| Parameter                                  | Description                              | Default                              |
| ------------------------------------------ | ---------------------------------------- | ------------------------------------ |
| `image.repository`                         | Container image repository               | `ghcr.io/openclaw/openclaw`          |
| `image.tag`                                | Container image tag                      | `2026.2.17`                          |
| `image.pullPolicy`                         | Image pull policy                        | `IfNotPresent`                       |
| `openclaw.agents.defaults.model`           | Primary model (provider/model format)    | `anthropic/claude-sonnet-4-20250514` |
| `openclaw.agents.defaults.timeoutSeconds`  | Agent timeout in seconds                 | `600`                                |
| `openclaw.agents.defaults.thinkingDefault` | Thinking mode (low/high/off)             | `low`                                |
| `openclaw.timezone`                        | Timezone environment variable            | `UTC`                                |
| `openclaw.bind`                            | Bind mode (localhost/lan)                | `localhost`                          |
| `openclaw.skills`                          | Skills to install from ClawHub           | `[]`                                 |
| `openclaw.configOverrides`                 | Raw JSON merged into openclaw.json       | `{}`                                 |
| `openclaw.configMode`                      | Config management mode (merge/overwrite) | `merge`                              |
| `credentials.anthropicApiKey`              | Anthropic API key                        | `""`                                 |
| `credentials.openaiApiKey`                 | OpenAI API key                           | `""`                                 |
| `credentials.existingSecret`               | Use existing secret                      | `""`                                 |
| `chromium.enabled`                         | Enable browser automation                | `true`                               |
| `persistence.enabled`                      | Enable persistent storage                | `true`                               |
| `persistence.size`                         | Storage size                             | `5Gi`                                |
| `ingress.enabled`                          | Enable ingress                           | `false`                              |

See [values.yaml](charts/openclaw/values.yaml) for all available configuration options.

</details>

### Using OpenAI instead of Anthropic

Set the OpenAI API key and switch the default model:

```bash
helm upgrade --install openclaw ./charts/openclaw \
  --set credentials.openaiApiKey="sk-..." \
  --set openclaw.agents.defaults.model="openai/gpt-4o" \
  # ... other flags (e.g. -f values-unsecure-google-auth.yaml, OAuth --set, etc.)
```

With `kind-test/deploy.sh` and Google OAuth:

```bash
export OPENAI_API_KEY="sk-..."
export GOOGLE_OAUTH_CLIENT_ID="..."
export GOOGLE_OAUTH_CLIENT_SECRET="..."
./kind-test/deploy.sh
```

Then set the default model to an OpenAI model (e.g. `openai/gpt-4o`) via a values file or `--set openclaw.agents.defaults.model=openai/gpt-4o` on install/upgrade.

**If your key is a project key (starts with `sk-proj-`), e.g. from the Default project:** set the project ID so the SDK sends the `OpenAI-Project` header. Get the Project ID from [Settings](https://platform.openai.com/settings) (select the project). Then:

```bash
helm upgrade openclaw ./charts/openclaw -n default --reuse-values \
  --set credentials.openaiProjectId="proj_xxxx"
# Optional for multi-org: --set credentials.openaiOrgId="org-xxxx"
kubectl rollout restart deployment/openclaw -n default
```

With `kind-test/deploy.sh`: `export OPENAI_PROJECT_ID="proj_xxxx"` before running deploy.

---

## Architecture

OpenClaw is deployed as a single-instance application with the following components:

- **Gateway** — Main WebSocket control plane on port `18789`
- **Canvas** — HTTP server on port `18793`
- **Chromium Sidecar** _(optional)_ — Headless browser for automation via CDP on port `9222`. Set `chromium.visibleMode: true` to use a VNC/noVNC image so you can watch the browser (port-forward 8080 to the chromium container).

> **Note:** The chart uses `Recreate` deployment strategy since OpenClaw is designed as a single-instance application and cannot be scaled horizontally.

---

## Storage

By default, the chart creates a PersistentVolumeClaim for storing OpenClaw configuration and state at `~/.openclaw/`:

```
├── agents
│   └── main
│       ├── agent
│       │   └── auth-profiles.json
│       └── sessions
│           ├── <session-id>.jsonl
│           └── sessions.json
├── canvas
│   └── index.html
├── credentials
│   ├── discord-allowFrom.json
│   └── discord-pairing.json
├── cron
│   ├── jobs.json
│   └── jobs.json.bak
├── devices
│   ├── paired.json
│   └── pending.json
├── identity
│   ├── device-auth.json
│   └── device.json
├── openclaw.json
├── update-check.json
└── workspace
    ├── AGENTS.md
    ├── HEARTBEAT.md
    ├── IDENTITY.md
    ├── memory
    │   └── <date>.md
    ├── SOUL.md
    ├── TOOLS.md
    └── USER.md
```

| Directory       | Purpose                                    |
| --------------- | ------------------------------------------ |
| `agents/`       | Agent sessions and authentication profiles |
| `canvas/`       | Web interface customizations               |
| `credentials/`  | Third-party service credentials            |
| `cron/`         | Scheduled jobs                             |
| `devices/`      | Paired devices for remote access           |
| `identity/`     | Device identity and authentication         |
| `workspace/`    | Agent memory and context files             |
| `openclaw.json` | Main configuration file                    |

<details>
<summary><b>Disable Persistence</b></summary>

To disable persistence (data will be lost on pod restart):

```bash
helm install openclaw openclaw/openclaw --set persistence.enabled=false
```

</details>

---

## Configuration Mode

OpenClaw is inherently stateful and updates its own configuration file at runtime (e.g., when installing skills or changing settings via the UI). By default, the chart uses `merge` mode to preserve these runtime changes.

| Mode                | Behavior                                                                                                          |
| ------------------- | ----------------------------------------------------------------------------------------------------------------- |
| `merge` _(default)_ | Merges Helm values with existing config. Runtime changes are preserved, Helm values take precedence on conflicts. |
| `overwrite`         | Completely replaces config on every pod restart. Runtime changes are lost.                                        |

```yaml
openclaw:
  configMode: "merge" # or "overwrite"
```

> **Tip:** Use `overwrite` mode if you want strict GitOps where Helm is the single source of truth.

---

## Security

> **Important:** OpenClaw is an AI agent with broad system access capabilities including shell execution, file system access, and browser automation. Be mindful of network exposure and access controls. See the [OpenClaw Security Guide](https://docs.openclaw.ai/gateway/security) for best practices.

The chart follows security best practices:

- All containers (including init) run as non-root (UID 1000)
- All capabilities are dropped
- Seccomp profiles are enabled
- Default bind is `localhost`; set `openclaw.bind: "lan"` only when you need network access
- Chromium CDP binds to `127.0.0.1` by default so only the OpenClaw container in the pod can connect
- Read-only root filesystem where possible

---

## Uninstallation

```bash
helm uninstall openclaw
```

> **Note:** The PersistentVolumeClaim is not automatically deleted. To remove it:

```bash
kubectl delete pvc openclaw
```

---

## Troubleshooting

<details>
<summary><b>Debug Commands</b></summary>

### Check pod status

```bash
kubectl get pods -l app.kubernetes.io/name=openclaw
```

### View logs

```bash
kubectl logs -l app.kubernetes.io/name=openclaw -c openclaw
```

### Access the gateway locally

```bash
kubectl port-forward svc/openclaw 18789:18789
```

### Chat / Control UI behind OAuth (no token in URL)

When using OAuth + gateway-nginx, the proxy injects the gateway token as `Authorization: Bearer`, `x-api-key`, `X-API-Key`, and `X-OpenClaw-API-Key` on every request to OpenClaw (including the WebSocket upgrade). **OpenClaw (from a build that includes WebSocket header-auth fallback)** accepts the token from these headers when the Control UI sends no token in the connect message. So you can use the UI without a token in the URL or pasted in Settings: user → gateway-auth-proxy (e.g. Google) → nginx (injects token) → OpenClaw gateway (uses token from headers). Build a new OpenClaw image from the openclaw repo (with the gateway WebSocket header-auth changes), push it, and use that image in the chart.

### Chat shows "HTTP 401 invalid x-api-key"

If you are on an older OpenClaw image that does not accept token from WebSocket upgrade headers, the Chat UI may expect the gateway token in an `x-api-key` (or `X-OpenClaw-API-Key`) header or in the URL. The gateway-nginx image injects the token on every request to OpenClaw; with the new OpenClaw build, the gateway uses that injected token for WebSocket auth when the UI sends none.

After rebuilding the OpenClaw image and running `./kind-test/deploy.sh`, **restart the gateway-nginx pods** so they use the new image (the `latest` tag doesn't trigger a pull when `imagePullPolicy: IfNotPresent`):

```bash
export KUBECONFIG=kind-test/kubeconfig
kubectl rollout restart deployment/openclaw-gateway-nginx -n default
```

Wait for the new pod to be ready, then retry Chat.

</details>

---

More detailed post at the [blog](https://metoro.io/blog/openclaw-kubernetes)

## License

This Helm chart is provided under the [MIT License](LICENSE).
