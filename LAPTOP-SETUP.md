# Agent Memory Server (V0) — laptop deployment (WORKING)

Redis-backed agent memory (working + long-term tiers, background extraction,
semantic search) over MCP, **fully local** — all inference runs in a local
Ollama container, no cloud keys, nothing leaves the network.

- Engine: https://github.com/redis/agent-memory-server (`V0/`, Apache-2.0).
- Runtime: **rootless podman**, all containers in a single **pod** named `agmem`.
- Status: ✅ running, Claude Code wired to `http://127.0.0.1:9050/sse`.

## Why a pod instead of podman-compose (important)

This laptop's rootless **netavark/nftables** bridge networking fails
(`netavark: nftables error: "nft" did not return successfully`), so a custom
compose bridge network won't start. The fix: run every container in **one pod**
(shared network namespace, pasta networking) — they talk over `localhost`, and
host access is via published ports. That's what `V0/run-pod.sh` does.

`V0/compose.podman.yml` is kept for hosts where netavark works (the Ubuntu GPU
box — see `GPU-BOX-SETUP.md`).

## Gotcha: use 127.0.0.1, not localhost

This host resolves `localhost` → `::1` (IPv6), but pasta forwards published ports
on **IPv4 only**. So always hit the services at **`127.0.0.1`**
(`http://localhost:...` resets the connection).

## Models

| Role | Model | Dims |
|------|-------|------|
| Embeddings | `nomic-embed-text` | 768 (`REDISVL_VECTOR_DIMENSIONS=768`) |
| Generation/extraction | `llama3.2:3b` | — (CPU; slow but fine for background work) |

Routed through Ollama's OpenAI-compatible API, so model names carry the
`openai/` prefix and `OPENAI_API_BASE=http://localhost:11434/v1`.
(The startup log says "dimensions: 1536" — cosmetic; that's a model-registry
fallback. The actual index is 768, proven by working semantic search.)

## Start / stop

```bash
cd ~/Documents/agent-memory-server/V0
./run-pod.sh                                   # (re)create the pod + containers

# one-time: pull the models into the ollama container
podman exec agmem-ollama ollama pull nomic-embed-text
podman exec agmem-ollama ollama pull llama3.2:3b

podman pod stop agmem        # stop
podman pod start agmem       # start again
podman pod rm -f agmem       # remove containers (named volumes redis_data/ollama_data persist)
```

Ports (pod-published): REST `:8000`, MCP/SSE `:9050`, Ollama `:11434`.

## Verify

```bash
curl -fsS http://127.0.0.1:8000/v1/health                       # {"now":...}
curl -fsS -N --max-time 3 http://127.0.0.1:9050/sse | head      # SSE stream opens

# round-trip semantic memory
curl -fsS -X POST http://127.0.0.1:8000/v1/long-term-memory/ -H 'Content-Type: application/json' \
  -d '{"memories":[{"id":"t1","text":"Andy prefers Ubuntu Server for the GPU box.","user_id":"andy","memory_type":"semantic"}]}'
sleep 6
curl -fsS -X POST http://127.0.0.1:8000/v1/long-term-memory/search -H 'Content-Type: application/json' \
  -d '{"text":"what OS does Andy want?","limit":3}'
```

## Claude Code wiring (done)

```bash
claude mcp add --transport sse --scope user memory http://127.0.0.1:9050/sse
claude mcp list | grep memory      # memory: ... (SSE) - ✔ Connected
```

Other agents on the tailnet can use the same memory at
`http://100.76.75.164:9050/sse` (DISABLE_AUTH=true — tailnet/localhost only,
never expose publicly).

## MCP tools

`memory_prompt`, `set_working_memory`, `search_long_term_memory`,
`get_long_term_memory`, `create_long_term_memories`, `edit_long_term_memory`,
`delete_long_term_memories`.
