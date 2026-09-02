---
name: ce-pickup
description: Extract session handoffs locally without frontier tokens.
version: 0.1.0
author: Wesley Matos (wesleymatosdev), Hermes Agent
license: MIT
platforms: [linux, macos]
metadata:
  hermes:
    tags: [handoff, session, context, ollama, hermes]
    related_skills: []
argument-hint: "SESSION_ID[,SESSION_ID,...] [MODEL] [OUT_DIR]"
---

# ce-pickup

Extracts ce-handoff/v1 documents from past Hermes sessions using a local model. Zero frontier token cost. Output is standard ce-handoff/v1 Markdown, so `/ce-handoff resume <path>` works immediately.

Use this instead of running `/ce-handoff` on a cold session that would burn subscription quota just to catch up.

## When to use

- User wants to resume a session they left unfinished without spending frontier tokens re-reading it
- You need a handoff from one or more past sessions but the context window is already loaded
- The user asks for a "pickup" or "catch-up" for an old session
- Running `/ce-handoff` on a large cold session would be expensive

## Quick start

```bash
bash ~/.hermes/scripts/ce-pickup.sh SESSION_ID[,SESSION_ID,...]
```

Outputs to `/tmp/compound-engineering-$(id -u)/ce-pickup/` by default.

Then resume from any output file:

```
/ce-handoff resume /tmp/compound-engineering-<uid>/ce-pickup/<slug>.md
```

## Arguments

- Arg 1 (required): comma-separated session IDs (from `session_search` or Hermes browse)
- Arg 2 (optional): Ollama model name — default `hf.co/ornith-ai/Ornith-1.5-35B-A3B-GGUF:Q5_K_M`
- Arg 3 (optional): output directory override

Env overrides (for tests and alternate hosts): `CE_PICKUP_DB` (default
`~/.hermes/state.db`), `CE_PICKUP_OLLAMA_URL` (default
`http://localhost:11434/api/chat`), `CE_PICKUP_MAX_CHARS` (default 24000).

## Model routing

Default: **Ornith-1.5-35B-A3B-GGUF:Q5_K_M** — verified good extraction quality, runs locally.

If Ornith is not loaded, any capable local Ollama model works. Do NOT use a frontier model (that defeats the purpose).

Check what is available: `ollama list`

## How it works

1. Reads `~/.hermes/state.db` via `sqlite3` — no Python, no TCC prompts
2. Extracts `user` + `assistant` messages ordered by timestamp
3. Truncates transcript to 24 000 chars (~6k tokens) — enough for meaningful extraction
4. Calls Ollama `/api/chat` via `curl` with a structured extraction prompt
5. Writes `ce-handoff/v1` frontmatter + model body to the output dir
6. Filename is a slug of the session title; numeric suffix on collision

## Output format

Every output file is valid `ce-handoff/v1` with:
- `artifact_contract: "ce-handoff/v1"` frontmatter
- `session_id`, `cwd`, `branch`, `repository` where available
- Extraction covering: objective, completed work, current state, decisions/constraints, blockers, failed approaches, references, next steps

## Context-ceiling watchdog (companion)

`scripts/context-ceiling-watchdog.sh` is a deterministic, no-agent monitor for
live session context. It estimates the current context of each live session
(`active=1` message content ÷ 4 chars/token — never use `sessions.input_tokens`,
which is cumulative billing volume including context re-reads) and enforces:

- `>= 50k` REMIND — one-line nudge, repeats hourly
- `>= 70k` ALERT — checkpoint warning, repeats every 30m
- `>= 80k` EXTRACT — runs ce-pickup locally and reports the ce-handoff/v1 path;
  after extraction, only re-alerts if the session climbs another ~10k (CRIT)

It is silent (empty stdout) unless a threshold fires, so it slots directly into
a no-agent cron job with change detection. State lives in
`~/.cache/context-ceiling-watchdog/` (flat TSV — no LLM memory, no recursive
continuity). It never writes to Hermes config or runtime state; state.db is
opened with sqlite3 `-readonly`.

Test it without a real model: `bash scripts/mock-ollama.sh 21143 &` then
`bash scripts/test-watchdog.sh` (fixture DB + scaled thresholds, 20 checks).

## Pitfalls

**TCC dialogs from Python** (macOS Sequoia+): Running Python as a subprocess of an app with broad entitlements can trigger TCC prompts for iCloud Drive or Documents — even when only reading `~/.hermes/state.db`. The shell script uses `sqlite3 + curl + jq + awk` only and does NOT trigger TCC. Never use a Python-based implementation of this workflow unless the user explicitly accepts TCC prompts.

**Transcript truncation**: 24k chars covers most sessions. Very long sessions (200+ messages with large tool outputs) get tail-truncated. If the handoff feels thin, split into narrower queries.

**Thinking models + num_predict**: Ollama's `num_predict` caps total generated tokens INCLUDING `message.thinking`. A thinking model (Ornith is one) can burn the entire budget in the thinking channel and return empty or tail-cut `message.content` — which the script reads exclusively. Symptom: "empty response from Ollama" or a handoff that stops mid-sentence, looking like a model-quality problem when it is a payload bug. The script sends `think:false` (with a retry-without-the-flag fallback for models that reject it). Scope note from Wesley: that flag is correct for this mechanical extraction job ONLY — Ornith's thinking is an asset in agentic engineering use, and an extraction run says nothing about agentic capability. Do not generalize a bad extraction into a verdict on the model.

**Ollama must be running**: Check with `ollama list` before invoking.

**Output is /tmp**: OS may reclaim on reboot. Copy to a stable path if resuming across reboots.

## Script

The canonical implementation is `scripts/ce-pickup.sh` in this skill — call it
by its skill path. A host-side copy historically lived at
`~/.hermes/scripts/ce-pickup.sh` (documented as a symlink); on machines where
that copy exists but is NOT a symlink, it is stale — trust the skill dir.

See also: `ce-handoff` skill for the resume workflow once the handoff doc exists.
