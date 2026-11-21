#!/usr/bin/env bash
# Run Agent Memory Server (V0), FULLY LOCAL, in a single rootless podman POD.
#
# Why a pod instead of `podman-compose`: this host's rootless netavark/nftables
# bridge errors out ("nft did not return successfully"). A pod puts every
# container in ONE network namespace (pasta networking, no custom bridge), so
# they reach each other over localhost. The compose.podman.yml file is kept for
# hosts where netavark works (e.g. the Ubuntu GPU box).
#
# All inference is local via the in-pod ollama (OpenAI-compatible API).
# After first run, pull the models:
#   podman exec agmem-ollama ollama pull nomic-embed-text
#   podman exec agmem-ollama ollama pull llama3.2:3b
set -euo pipefail

POD=agmem
IMG=docker.io/redislabs/agent-memory-server:0.15.2
REDIS_IMG=docker.io/redis/redis-stack-server:latest
OLLAMA_IMG=docker.io/ollama/ollama:latest

# Shared env for the agent-memory services. localhost = other pod members.
ENV=(
  -e REDIS_URL=redis://localhost:6379
  -e LONG_TERM_MEMORY=True
  -e ENABLE_TOPIC_EXTRACTION=True
  -e ENABLE_NER=True
  -e DISABLE_AUTH=true
  -e OPENAI_API_BASE=http://localhost:11434/v1
  -e OPENAI_API_KEY=ollama
  -e GENERATION_MODEL=openai/llama3.2:3b
  -e EMBEDDING_MODEL=openai/nomic-embed-text
  -e SLOW_MODEL=openai/llama3.2:3b
  -e FAST_MODEL=openai/llama3.2:3b
  -e REDISVL_VECTOR_DIMENSIONS=768
)

podman pod rm -f "$POD" 2>/dev/null || true
podman pod create --name "$POD" \
  -p 8000:8000 \
  -p 9050:9000 \
  -p 11434:11434

podman run -d --pod "$POD" --name agmem-redis  --restart unless-stopped \
  -v redis_data:/data "$REDIS_IMG"

podman run -d --pod "$POD" --name agmem-ollama --restart unless-stopped \
  -e OLLAMA_HOST=0.0.0.0:11434 \
  -v ollama_data:/root/.ollama "$OLLAMA_IMG"

podman run -d --pod "$POD" --name agmem-api    --restart unless-stopped \
  "${ENV[@]}" -e PORT=8000 "$IMG" agent-memory api --host 0.0.0.0 --port 8000

podman run -d --pod "$POD" --name agmem-mcp    --restart unless-stopped \
  "${ENV[@]}" "$IMG" agent-memory mcp --mode sse --port 9000

podman run -d --pod "$POD" --name agmem-worker --restart unless-stopped \
  "${ENV[@]}" "$IMG" agent-memory task-worker

echo
echo "pod '$POD' started."
echo "  REST API : http://localhost:8000"
echo "  MCP (SSE): http://localhost:9050/sse"
echo "  Ollama   : http://localhost:11434"
