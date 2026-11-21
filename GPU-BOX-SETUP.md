# GPU box — Agent Memory Server (NixOS, fully local, all-in-one)

The dedicated box **`neutron`** (NixOS 25.11, Intel i5-9400F, **NVIDIA RTX 5060 Ti
8 GB**) hosts the whole stack — Ollama + Redis + the memory API/MCP/worker — with
all inference on the GPU. Laptop Claude and other agents on the LAN/tailnet point
at it. Status: ✅ deployed and verified 2026-11-21.

- Host IP: **192.168.1.132** (LAN). REST `:8000`, MCP/SSE `:9050`.
- Point clients at: **http://192.168.1.132:9050/sse**

## How it's deployed (declarative — no manual apt/compose)

Everything is one NixOS module, imported by the flake host `neutron-metal`:

- Config repo (flake): `~/.config/nixos/nixos-config` (`github:agomerz/nixos-config`),
  nixpkgs **unstable**, `allowUnfree = true`.
- The module: **`src/modules/agent-memory.nix`**, imported from
  `src/hosts/metal/configuration.nix`.
- Rebuild: `sudo nixos-rebuild switch --flake .#neutron-metal` (run from the repo).

The module sets up, in order:

1. **NVIDIA driver** — `nvidiaPackages.production` (570.181) with
   `hardware.nvidia.open = true`. **Blackwell (RTX 50xx) REQUIRES the open kernel
   modules**; the `production` branch (≥570) supports it. (There is no iGPU on the
   i5-9400**F**, so there is NO PRIME offload — the dGPU drives everything.)
2. **Podman + NVIDIA Container Toolkit** — rootful `oci-containers` (backend
   podman) and `hardware.nvidia-container-toolkit.enable = true`, which
   auto-generates the CDI spec so a container can request `nvidia.com/gpu=all`.
3. **The stack** — five containers, all on the **host network namespace** (they
   talk over `127.0.0.1`; no bridge/netavark DNS to break), named `agmem-ollama`
   (gets the GPU), `agmem-redis` (AOF on), `agmem-api`, `agmem-mcp`, `agmem-worker`.
   Named volumes `redis_data` / `ollama_data` persist across rebuilds.
4. **DNS fix** (see gotcha below) + an idempotent model-pull service.
5. **Firewall** — only `8000` + `9050` are open to the LAN. Redis (6379) and Ollama
   (11434) are bound to `127.0.0.1` and firewalled off.

### Models

| Role | Model | Dims |
|------|-------|------|
| Embeddings | `nomic-embed-text` | 768 (`REDISVL_VECTOR_DIMENSIONS=768`) |
| Generation/extraction | `llama3.1:8b` (Q4) | — (on GPU) |

`nomic-embed-text` (~0.3 GB) + `llama3.1:8b` (~5.3 GB) ≈ 5.7 GB of the 8 GB card.
Both run **100% on GPU**. 14B won't fit — don't. Switching the embedding model
changes vector dims → wipe + re-embed.

## Gotcha: DNS at boot (fixed in the module)

The DHCP-handed resolver list included a dead IPv6 server and a wrong-subnet IPv4
one; ollama's Go resolver hung on them, so `ollama pull` failed at boot ("i/o
timeout … registry.ollama.ai"). The module pins working DNS and stops dhcpcd from
overwriting it:

```nix
networking.nameservers = [ "192.168.1.1" "1.1.1.1" ];
networking.dhcpcd.extraConfig = "nohook resolv.conf";
```

Runtime inference is fully local and needs no DNS — this only affects model pulls.
After the first pull the models live in `ollama_data`, so reboots never re-pull.

## Gotcha: nixos-rebuild as root over SSH (git "dubious ownership")

The flake repo is owned by `andy`; `nix` (libgit2) refuses it as root unless
`safe.directory` is in the gitconfig that root's `$HOME` points at. `sudo -E`
works (keeps a HOME whose fallback is `/root`, and `/root/.gitconfig` trusts the
repo). If running from a bare systemd/root context, set `HOME=/root` and ensure
`/root/.gitconfig` has `safe.directory = /home/andy/.config/nixos/nixos-config`.

## Verify

```bash
nvidia-smi                                   # RTX 5060 Ti, driver 570.181
sudo podman exec agmem-ollama ollama ps      # both models 100% GPU
curl -fsS http://127.0.0.1:8000/v1/health    # {"now":...}
curl -fsS -N --max-time 3 http://127.0.0.1:9050/sse | head   # SSE opens

# round-trip semantic memory
curl -fsS -X POST http://127.0.0.1:8000/v1/long-term-memory/ -H 'Content-Type: application/json' \
  -d '{"memories":[{"id":"t1","text":"neutron is the GPU memory box.","user_id":"andy","memory_type":"semantic"}]}'
sleep 6
curl -fsS -X POST http://127.0.0.1:8000/v1/long-term-memory/search -H 'Content-Type: application/json' \
  -d '{"text":"what is the GPU box?","limit":3}'
```

## Wire clients

On the laptop (and any other agent), point Claude Code at the box over the LAN/tailnet:

```bash
claude mcp add --transport sse --scope user memory http://192.168.1.132:9050/sse
claude mcp list | grep memory      # memory: ... (SSE) - ✔ Connected
```

(Replace the laptop-local `http://127.0.0.1:9050/sse` entry — remove with
`claude mcp remove memory` first.) DISABLE_AUTH=true → keep on the LAN/tailnet
only, never expose publicly.

## Run on boot

Nothing extra needed — the `oci-containers` systemd units have
`restart = unless-stopped` and start at boot; the model-pull service is idempotent
and non-fatal. A reboot comes back fully functional with no manual steps.

## 7. Persistence / durability

All memories live in **Redis**, persisted to the named volume `redis_data`
(`/data`, holds `dump.rdb` + the AOF). It survives container/pod restarts and
rebuilds — only `podman volume rm redis_data` wipes it. Models live in `ollama_data`.

**AOF is enabled** (the redis container runs
`redis-stack-server --appendonly yes --bind 127.0.0.1`), so every write is logged —
a hard crash loses at most the last write, not minutes of data.

## 8. Migrate memories between servers (laptop → neutron, or box → box)

Memories = text + metadata + **embedding vectors**. The one rule: **vectors are only
valid for the embedding model that made them.** Both the laptop and neutron use
`nomic-embed-text` (768 dims), so a raw Redis copy works. Only the *generation*
model differing (laptop `llama3.2:3b` → neutron `llama3.1:8b`) does NOT affect
stored vectors.

### Method 1 — raw Redis copy (same embedding model; fast, exact)

```bash
# SOURCE (e.g. laptop pod): flush to disk and pull the dump out
podman exec agmem-redis redis-cli SAVE
podman cp agmem-redis:/data/dump.rdb ./memory-dump.rdb
scp ./memory-dump.rdb andy@192.168.1.132:~/

# TARGET (neutron): stop the stack, drop the dump into the volume, start
sudo systemctl stop podman-agmem-redis
sudo podman run --rm -v redis_data:/data -v "$PWD":/src docker.io/library/busybox \
  cp /src/memory-dump.rdb /data/dump.rdb
sudo systemctl start podman-agmem-redis
sudo podman exec agmem-redis redis-cli dbsize   # confirm key count matches source
```

With AOF on, the target rebuilds the AOF from the RDB on start.

### Method 2 — app-level export → import (model-agnostic; re-embeds on target)

Use when the embedding model/dimensions change (old vectors can't be reused). Pull
every long-term memory from the source and POST to the target, which re-embeds:

```bash
curl -s -X POST http://<source>:8000/v1/long-term-memory/search \
  -H 'Content-Type: application/json' -d '{"text":"*","limit":1000}' > memories.json
# reshape to {"memories":[...]} and POST to:
curl -s -X POST http://192.168.1.132:8000/v1/long-term-memory/ \
  -H 'Content-Type: application/json' -d @payload.json
```

- Survives an embedding-model swap; more robust but scripted.
- **Working memory** (per-session, 1-hour TTL) is not worth migrating — long-term only.
- Do migrations while the source is idle so no in-flight writes are missed.
