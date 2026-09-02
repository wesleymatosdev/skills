#!/usr/bin/env bash
# ce-pickup: extract ce-handoff/v1 docs from Hermes sessions via a local Ollama model.
# Uses only: sqlite3, curl, jq, awk — no Python, no TCC prompts.
#
# Usage:
#   ce-pickup.sh SESSION_ID[,SESSION_ID,...] [MODEL] [OUT_DIR]
#
# Defaults:
#   MODEL:   hf.co/ornith-ai/Ornith-1.5-35B-A3B-GGUF:Q5_K_M
#   OUT_DIR: /tmp/compound-engineering-$(id -u)/ce-pickup/

set -euo pipefail

SESSIONS_ARG="${1:-}"
MODEL="${2:-hf.co/ornith-ai/Ornith-1.5-35B-A3B-GGUF:Q5_K_M}"
DB="${CE_PICKUP_DB:-${HOME}/.hermes/state.db}"
OLLAMA_URL="${CE_PICKUP_OLLAMA_URL:-http://localhost:11434/api/chat}"
MAX_CHARS="${CE_PICKUP_MAX_CHARS:-24000}"

if [[ -z "$SESSIONS_ARG" ]]; then
  echo "Usage: ce-pickup.sh SESSION_ID[,SESSION_ID,...] [MODEL] [OUT_DIR]" >&2
  exit 1
fi

UID_VAL="$(id -u)"
SCRATCH_ROOT="/tmp/compound-engineering-${UID_VAL}"
if [[ -L "$SCRATCH_ROOT" ]]; then
  echo "ERROR: scratch root is a symlink: $SCRATCH_ROOT" >&2; exit 1
fi
mkdir -m 700 -p "$SCRATCH_ROOT"
chmod 700 "$SCRATCH_ROOT"

OUT_DIR="${3:-${SCRATCH_ROOT}/ce-pickup}"
mkdir -m 700 -p "$OUT_DIR"

slug() {
  echo "$1" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]/-/g' | sed 's/-\+/-/g' | sed 's/^-//;s/-$//' | cut -c1-40
}

IFS=',' read -ra SESSION_IDS <<< "$SESSIONS_ARG"

for SID in "${SESSION_IDS[@]}"; do
  SID="${SID// /}"
  echo ""
  echo "Processing session: $SID"

  META=$(sqlite3 "$DB" \
    "SELECT id, COALESCE(title, display_name, id), COALESCE(cwd,'unknown'), \
            COALESCE(started_at,''), COALESCE(git_branch,''), COALESCE(git_repo_root,'') \
     FROM sessions WHERE id='${SID}' LIMIT 1;")
  if [[ -z "$META" ]]; then
    echo "  ERROR: session not found: $SID" >&2; continue
  fi

  IFS='|' read -r SID_OUT TITLE CWD STARTED_AT GIT_BRANCH GIT_REPO <<< "$META"
  echo "  title: $TITLE"

  MESSAGES=$(sqlite3 "$DB" \
    "SELECT role, SUBSTR(COALESCE(content,''), 1, 1600), COALESCE(tool_name,'')
     FROM messages
     WHERE session_id='${SID}' AND active=1
     AND role IN ('user','assistant','tool')
     ORDER BY timestamp ASC;")

  MSG_COUNT=$(echo "$MESSAGES" | grep -c '|' || true)
  echo "  messages: ~$MSG_COUNT"

  TRANSCRIPT=$(echo "$MESSAGES" | awk -F'|' -v max="$MAX_CHARS" '
  BEGIN { total=0; truncated=0 }
  {
    role=$1; content=$2; tool=$3
    if (role == "user") line = "USER: " content
    else if (role == "assistant") line = "ASSISTANT: " content
    else if (role == "tool") line = "[TOOL: " tool "]\n" substr(content,1,600)
    else next

    if (total + length(line) > max) {
      if (!truncated) { print "\n...[transcript truncated for length]"; truncated=1 }
      next
    }
    total += length(line)
    print line
  }
  ')

  CHAR_COUNT=${#TRANSCRIPT}
  echo "  transcript chars: $CHAR_COUNT"

  SYSTEM_MSG="You are a precise session-handoff extractor. Given a conversation transcript, produce a structured handoff a fresh agent can use to orient instantly. Be pointer-first: reference paths, commits, URLs, file names rather than reproducing content. Be concise. Output raw Markdown only."

  USER_MSG="Extract a handoff from the transcript below. Cover:\n\n1. **Objective** - what the user was trying to accomplish\n2. **Work completed** - what was actually done and verified\n3. **Current state** - what exists, what is partial, what is missing\n4. **Key decisions & constraints** - choices made and why, rejected alternatives\n5. **Blockers / unfinished work** - what is pending, what depends on what\n6. **Failed / abandoned approaches** - wrong paths the next agent might retry\n7. **Authoritative references** - key files, commits, URLs (what matters there)\n8. **Next steps** - concrete recommended continuation\n\nAttribute intent to the user only when the transcript clearly shows the user stated it. Mark inferences as '(inferred)'. Redact secrets/credentials.\n\n---\nTRANSCRIPT:\n${TRANSCRIPT}"

  # think:false keeps thinking models (e.g. Ornith) from burning num_predict
  # on message.thinking and emitting empty content. Models that don't support
  # thinking reject the flag, so retry without it on that specific error.
  build_payload() {
    jq -n \
      --arg model "$MODEL" \
      --arg sys "$SYSTEM_MSG" \
      --arg usr "$USER_MSG" \
      --argjson think "$1" \
      '{
        model: $model,
        messages: [
          {role: "system", content: $sys},
          {role: "user",   content: $usr}
        ],
        stream: false,
        think: $think,
        options: {temperature: 0.2, num_predict: 2048}
      }'
  }

  echo "  calling Ollama (${MODEL##*/})..."
  RESPONSE=$(curl -s --max-time 300 -X POST "$OLLAMA_URL" \
    -H "Content-Type: application/json" \
    -d "$(build_payload false)")
  if echo "$RESPONSE" | grep -qi 'does not support thinking'; then
    RESPONSE=$(curl -s --max-time 300 -X POST "$OLLAMA_URL" \
      -H "Content-Type: application/json" \
      -d "$(build_payload true)")
  fi

  BODY=$(echo "$RESPONSE" | jq -r '.message.content // empty')
  if [[ -z "$BODY" ]]; then
    echo "  ERROR: empty response from Ollama" >&2
    echo "  Raw: $(echo "$RESPONSE" | head -c 400)" >&2
    continue
  fi

  TOPIC=$(slug "$TITLE")
  OUTFILE="${OUT_DIR}/${TOPIC}.md"
  SUFFIX=1
  while [[ -e "$OUTFILE" ]]; do
    OUTFILE="${OUT_DIR}/${TOPIC}-${SUFFIX}.md"
    SUFFIX=$((SUFFIX+1))
  done

  NOW=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
  STARTED_FMT=$(date -r "${STARTED_AT%%.*}" -u +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || echo "$STARTED_AT")

  {
    echo '---'
    echo "artifact_contract: \"ce-handoff/v1\""
    echo "created_at: \"${NOW}\""
    printf 'title: "%s"\n' "${TITLE//\"/\'}"
    echo "summary: \"Pickup handoff extracted from session ${SID} (started ${STARTED_FMT})\""
    echo 'keywords: ["ce-pickup", "session-handoff", "'${SID:0:16}'"]'
    echo "cwd: \"${CWD}\""
    echo "session_id: \"${SID}\""
    [[ -n "$GIT_BRANCH"  ]] && echo "branch: \"${GIT_BRANCH}\""
    [[ -n "$GIT_REPO"    ]] && echo "repository: \"${GIT_REPO}\""
    echo '---'
    echo ''
    echo "$BODY"
  } > "$OUTFILE"

  echo "  written: $OUTFILE"
  echo "  resume:  /ce-handoff resume $OUTFILE"
done

echo ""
echo "--- ce-pickup complete ---"
echo "Output dir: $OUT_DIR"
