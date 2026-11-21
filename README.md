# agent-memory-deploy

Deployment docs + config for my self-hosted, **fully-local** Redis
[Agent Memory Server](https://github.com/redis/agent-memory-server) (OSS V0):
working + long-term memory over MCP, all inference on a local Ollama (no cloud
keys), shared across my Claude and other AI agents.

> ⚠️ Private infra notes. The server runs with **auth disabled** — keep it on the
> LAN/tailnet only, never public. Contains internal hostnames/IPs.

## Current setup

- **Live server**: the GPU box **neutron** (NixOS, RTX 5060 Ti) at
  `192.168.1.132` — REST `:8000`, MCP/SSE `:9050`. See **[GPU-BOX-SETUP.md](GPU-BOX-SETUP.md)**.
  Its NixOS config lives in [`agomerz/nixos-config`](https://github.com/agomerz/nixos-config)
  (`src/modules/agent-memory.nix`).
- **Laptop fallback**: a rootless podman pod (currently stopped). See
  **[LAPTOP-SETUP.md](LAPTOP-SETUP.md)** and `V0/`.

## Contents

| File | What |
|------|------|
| `GPU-BOX-SETUP.md` | The NixOS GPU-box deployment (driver, podman/CDI, stack, DNS fix, persistence, migration). |
| `LAPTOP-SETUP.md` | The laptop rootless-podman pod deployment (netavark workaround, gotchas). |
| `AGENT-MEMORY-PROMPT.md` | Copy-paste prompt to let another agent use the shared memory server. |
| `V0/compose.podman.yml` | Laptop compose (CPU). |
| `V0/compose.podman.gpu.yml` | Compose variant with GPU (for a non-NixOS GPU host). |
| `V0/run-pod.sh` | The working laptop launcher (single podman pod). |
| `V0/.env.example` | Env note — no secrets needed in the fully-local setup. |

These are copies kept for reference/backup; the live files run from their
machines (the laptop clone's `V0/`, and neutron's NixOS module).
