# Prompt: let another agent use the shared memory server

Hand this to any other AI agent so it can read/write Andy's shared, persistent
agent memory (hosted on the GPU box **neutron**, `192.168.1.132`). Memories are
shared across all agents and persist across sessions.

- MCP (SSE): `http://192.168.1.132:9050/sse`
- REST API : `http://192.168.1.132:8000`
- No API key (inference is fully local). **Auth is disabled — LAN/tailnet only.**

---

## For an MCP-capable agent (e.g. Claude Code)

Connect once:

```bash
claude mcp add --transport sse --scope user memory http://192.168.1.132:9050/sse
```

Then paste this into the agent (system prompt or first message):

```
You have access to a shared, persistent memory server over MCP (server name:
"memory"). It is a Redis-backed agent-memory service that all of Andy's agents
share, so memories you store are visible to other agents and persist across
sessions. Use it actively.

CONVENTIONS (follow these so the shared memory stays consistent):
- Always use user_id "andy" for every read and write, unless told otherwise.
- At the START of a task, SEARCH memory for relevant context before asking Andy
  or making assumptions. Use a natural-language query describing what you need
  (search is semantic, not keyword).
- STORE a long-term memory whenever you learn a durable, reusable fact: a stable
  preference, a decision, an environment/infra detail, a convention, or anything
  Andy would expect you to remember next time. Write ONE clean fact per memory,
  phrased as a standalone statement (e.g. "Andy's GPU box 'neutron' runs the
  memory server at 192.168.1.132:9050"), not your reasoning or a transcript.
- Do NOT store secrets, credentials, throwaway test data, or ephemeral chatter.
- Before storing, search first; if a matching memory exists, edit/update it
  instead of creating a near-duplicate.
- Use working memory for within-session scratch state; use long-term memory for
  anything that should outlive the session.

TOOLS (from the "memory" MCP server):
- search_long_term_memory  — semantic search; your default "recall" tool.
- create_long_term_memories — store new durable facts (set user_id "andy").
- get_long_term_memory / edit_long_term_memory / delete_long_term_memories
- set_working_memory        — per-session scratch state.
- memory_prompt             — pull relevant memories to ground a response.

If any memory tool errors or the server is unreachable, tell Andy rather than
silently proceeding without memory.
```

---

## For an agent that can't do MCP but can make HTTP calls

Same server, REST API on port 8000:

```
Store:  POST http://192.168.1.132:8000/v1/long-term-memory/
        body: {"memories":[{"text":"<one clean fact>","user_id":"andy","memory_type":"semantic"}]}
Recall: POST http://192.168.1.132:8000/v1/long-term-memory/search
        body: {"text":"<natural-language query>","limit":5}
```

---

## Caveats

- **Network**: the agent must be on Andy's LAN (or tailnet) to reach
  `192.168.1.132`. Auth is disabled, so keep the server off the public internet.
  For remote agents, put neutron on Tailscale and hand out the tailnet IP.
- Server details and operations: see `GPU-BOX-SETUP.md`.
