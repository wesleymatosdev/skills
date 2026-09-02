#!/usr/bin/env bash
# context-ceiling-watchdog.sh — deterministic, no-agent session context monitor.
#
# Watches live Hermes sessions in state.db and enforces agreed context-ceiling
# thresholds (estimated current-context tokens from active message content):
#
#   >= 50k  REMIND    one-line nudge (repeat every REMIND_EVERY_MINS)
#   >= 70k  ALERT     stronger checkpoint warning (repeat every ALERT_EVERY_MINS)
#   >= 80k  EXTRACT   runs ce-pickup.sh locally (Ollama) to produce a
#                     ce-handoff/v1 doc, then reports the artifact path
#
# Design constraints (kanban card t_575acbf3):
#   - Deterministic no-agent monitoring: pure sqlite3/awk, no LLM calls
#     except the 80k auto-extraction, which uses the local ce-pickup flow.
#   - No recursive cron continuity: state is a flat TSV file, no LLM memory.
#   - Never mutates Hermes config or runtime state; reads state.db readonly.
#
# Output contract: one stdout line per action; EMPTY stdout when everything
# is below thresholds or inside hysteresis windows (so a no-agent cron job
# stays silent and only delivers when something happens).
#
# Env overrides for tests: CE_WATCHDOG_DB, _WARN_TOKENS, _ALERT_TOKENS,
# _EXTRACT_TOKENS, _CHAR_PER_TOKEN, _FRESH_SECS, _REMIND_EVERY_MINS,
# _ALERT_EVERY_MINS, _CRIT_DELTA_TOKENS, _PICKUP_SCRIPT, _PICKUP_MODEL,
# _OLLAMA_URL, _STATE_DIR, _OUT_DIR, _MAX_AUTO_EXTRACTS, _NOW.
set -euo pipefail

DB="${CE_WATCHDOG_DB:-${HOME}/.hermes/state.db}"
WARN_TOKENS="${CE_WATCHDOG_WARN_TOKENS:-50000}"
ALERT_TOKENS="${CE_WATCHDOG_ALERT_TOKENS:-70000}"
EXTRACT_TOKENS="${CE_WATCHDOG_EXTRACT_TOKENS:-80000}"
CHAR_PER_TOKEN="${CE_WATCHDOG_CHAR_PER_TOKEN:-4}"
FRESH_SECS="${CE_WATCHDOG_FRESH_SECS:-1800}"                 # "live" = activity within N secs
REMIND_EVERY_MINS="${CE_WATCHDOG_REMIND_EVERY_MINS:-60}"
ALERT_EVERY_MINS="${CE_WATCHDOG_ALERT_EVERY_MINS:-30}"
CRIT_DELTA_TOKENS="${CE_WATCHDOG_CRIT_DELTA_TOKENS:-10000}"  # post-extract re-escalation
PICKUP_SCRIPT="${CE_WATCHDOG_PICKUP_SCRIPT:-${HOME}/.hermes/skills/ce-pickup/scripts/ce-pickup.sh}"
PICKUP_MODEL="${CE_WATCHDOG_PICKUP_MODEL:-}"                 # empty = ce-pickup default
PICKUP_OLLAMA_URL="${CE_WATCHDOG_OLLAMA_URL:-}"              # forwarded as CE_PICKUP_OLLAMA_URL
STATE_DIR="${CE_WATCHDOG_STATE_DIR:-${HOME}/.cache/context-ceiling-watchdog}"
OUT_DIR="${CE_WATCHDOG_OUT_DIR:-${HOME}/.cache/context-ceiling-watchdog/handoffs}"
MAX_AUTO_EXTRACTS="${CE_WATCHDOG_MAX_AUTO_EXTRACTS:-3}"      # per tick, load guard
NOW="${CE_WATCHDOG_NOW:-$(date +%s)}"

STATE_FILE="${STATE_DIR}/sessions.state"

# --- State helpers (TSV: sid<TAB>level<TAB>level_est<TAB>last_emit) ---------
state_field() { # $1=sid $2=field(1..4) -> value or ""
  awk -F'\t' -v s="$1" -v f="$2" '$1==s {print $f; found=1} END{if(!found) print ""}' "$STATE_FILE"
}

upsert_state() { # $1=sid $2=level $3=est $4=last_emit
  local sid="$1" lvl="$2" est="$3" ts="$4" tmp
  tmp=$(mktemp)
  awk -F'\t' -v s="$sid" '$1!=s' "$STATE_FILE" > "$tmp"
  printf '%s\t%s\t%s\t%s\n' "$sid" "$lvl" "$est" "$ts" >> "$tmp"
  mv "$tmp" "$STATE_FILE"
}

drop_state() { # $1=sid
  local tmp
  tmp=$(mktemp)
  awk -F'\t' -v s="$1" '$1!=s' "$STATE_FILE" > "$tmp"
  mv "$tmp" "$STATE_FILE"
}

# --- Fresh live sessions with active-context size ---------------------------
# active=1 rows are the live context (compaction sets active=0); ~4 chars/token.
query_sessions() {
  sqlite3 -readonly -cmd "PRAGMA busy_timeout=3000;" "$DB" \
    "SELECT s.id, COALESCE(s.title, s.display_name, s.id),
            COALESCE(SUM(LENGTH(COALESCE(m.content,''))),0)
     FROM sessions s
     LEFT JOIN messages m
       ON m.session_id = s.id AND m.active = 1
      AND m.role IN ('user','assistant','tool')
     WHERE s.ended_at IS NULL
       AND COALESCE(s.archived,0) = 0
       AND COALESCE(s.hidden,0) = 0
       AND COALESCE(s.last_activity_at, s.started_at) > ($NOW - $FRESH_SECS)
     GROUP BY s.id
     ORDER BY 3 DESC;"
}

# --- Auto-extract via ce-pickup (local Ollama); echoes path on success ------
run_pickup() { # $1=sid
  local sid="$1" before after newfile
  before=$(ls "$OUT_DIR" 2>/dev/null | wc -l | tr -d ' ')
  CE_PICKUP_DB="$DB" CE_PICKUP_OLLAMA_URL="$PICKUP_OLLAMA_URL" \
    bash "$PICKUP_SCRIPT" "$sid" "$PICKUP_MODEL" "$OUT_DIR" >/dev/null 2>&1 || true
  after=$(ls "$OUT_DIR" 2>/dev/null | wc -l | tr -d ' ')
  if (( after > before )); then
    newfile=$(ls -t "$OUT_DIR" 2>/dev/null | head -1)
    [[ -n "$newfile" ]] && newfile="$OUT_DIR/$newfile"
    # cheap ce-handoff/v1 contract check before claiming success
    if [[ -n "$newfile" ]] && head -20 "$newfile" | grep -q 'artifact_contract: "ce-handoff/v1"'; then
      echo "$newfile"
      return 0
    fi
  fi
  return 1
}

# --- Main -------------------------------------------------------------------
mkdir -m 700 -p "$STATE_DIR" "$OUT_DIR"
touch "$STATE_FILE"

EMU=0
while IFS='|' read -r SID TITLE CHARS; do
  [[ -z "${SID:-}" ]] && continue
  EST=$(( CHARS / CHAR_PER_TOKEN ))
  LVL=$(state_field "$SID" 2); [[ -z "$LVL" ]] && LVL=none
  LVL_EST=$(state_field "$SID" 3); LVL_EST="${LVL_EST:-$EST}"
  LVL_TS=$(state_field "$SID" 4); LVL_TS="${LVL_TS:-0}"
  DUE=$(( (NOW - LVL_TS) >= REMIND_EVERY_MINS * 60 ? 1 : 0 ))
  DUE_ALERT=$(( (NOW - LVL_TS) >= ALERT_EVERY_MINS * 60 ? 1 : 0 ))

  if (( EST < WARN_TOKENS )); then
    [[ "$LVL" != "none" ]] && drop_state "$SID"   # back under floor: clear silently
    continue
  fi

  TITLE_SHORT=$(printf '%s' "$TITLE" | tr '\t\n' '  ' | cut -c1-48)

  if (( EST >= EXTRACT_TOKENS )); then
    case "$LVL" in
      extracted)
        if (( EST - LVL_EST >= CRIT_DELTA_TOKENS )) && (( DUE_ALERT )); then
          echo "[ctx-watchdog] CRIT session ${SID} (~${EST} tokens, +$(( EST - LVL_EST )) since extract): still climbing — intervene or /ce-handoff create now"
          upsert_state "$SID" "extracted" "$EST" "$NOW"
        fi
        ;;
      extract-failed)
        # retry each tick; only re-announce on the alert cadence
        if (( EMU < MAX_AUTO_EXTRACTS )); then
          HANDOFF=$(run_pickup "$SID" || true)
          EMU=$(( EMU + 1 ))
          if [[ -n "${HANDOFF:-}" && -s "$HANDOFF" ]]; then
            echo "[ctx-watchdog] EXTRACT session ${SID} (~${EST} tokens): auto ce-pickup → ${HANDOFF}"
            upsert_state "$SID" "extracted" "$EST" "$NOW"
          elif (( DUE_ALERT )); then
            echo "[ctx-watchdog] FAIL session ${SID} (~${EST} tokens): auto-extract failed (ollama down?) — run ce-pickup.sh manually"
            upsert_state "$SID" "extract-failed" "$EST" "$NOW"
          fi
        fi
        ;;
      *)
        if (( EMU < MAX_AUTO_EXTRACTS )); then
          HANDOFF=$(run_pickup "$SID" || true)
          EMU=$(( EMU + 1 ))
          if [[ -n "${HANDOFF:-}" && -s "$HANDOFF" ]]; then
            echo "[ctx-watchdog] EXTRACT session ${SID} (~${EST} tokens): auto ce-pickup → ${HANDOFF}"
            upsert_state "$SID" "extracted" "$EST" "$NOW"
          else
            echo "[ctx-watchdog] FAIL session ${SID} (~${EST} tokens): auto-extract failed (ollama down?) — run ce-pickup.sh manually"
            upsert_state "$SID" "extract-failed" "$EST" "$NOW"
          fi
        fi
        ;;
    esac
  elif (( EST >= ALERT_TOKENS )); then
    if [[ "$LVL" == "none" || "$LVL" == "reminded" || "$LVL" == "extract-failed" ]] \
       || [[ "$LVL" == "alerted" && $DUE_ALERT -eq 1 ]]; then
      echo "[ctx-watchdog] ALERT session ${SID} (~${EST} tokens est, ${TITLE_SHORT}): context ceiling near — checkpoint now (/ce-handoff create)"
      upsert_state "$SID" "alerted" "$EST" "$NOW"
    fi
  else # WARN zone
    if [[ "$LVL" == "none" ]] || [[ "$LVL" == "reminded" && $DUE -eq 1 ]]; then
      echo "[ctx-watchdog] REMIND session ${SID} (~${EST} tokens est, ${TITLE_SHORT}): consider /ce-handoff checkpoint"
      upsert_state "$SID" "reminded" "$EST" "$NOW"
    fi
  fi
done < <(query_sessions)

# silence when nobody breached
exit 0
