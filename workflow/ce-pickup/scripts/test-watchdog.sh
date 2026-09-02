#!/usr/bin/env bash
# Synthetic-threshold test harness for context-ceiling-watchdog.sh.
# Fixture DB + mock Ollama + scaled-down thresholds (4 chars = 1 "token") so
# every level is reachable without a huge transcript.
#
# Scenarios:
#   0. below floor            -> silent, no state
#   1. warn zone              -> one REMIND, silent on repeat inside window
#   2. alert zone             -> REMIND->ALERT escalation, silent on repeat
#   3. extract zone           -> EXTRACT via mock ce-pickup, valid ce-handoff/v1
#   4. post-extract climb     -> CRIT once, then silent
#   5. fail-then-recover      -> FAIL, cadence re-FAIL, then recovery EXTRACT
#   6. post-extract quiet     -> no re-nag in lower zones once extracted
#   7. drop under floor       -> state cleared (fresh REMIND on re-entry)
#
# Requires: mock Ollama running on :21143 (bash scripts/mock-ollama.sh 21143 &)
# and scripts/fixture-db.sh present next to this test.
set -euo pipefail
cd "$(dirname "$0")/.."   # skill dir

WATCHDOG="$PWD/scripts/context-ceiling-watchdog.sh"
PICKUP="$PWD/scripts/ce-pickup.sh"
FIXTURE="$PWD/scripts/fixture-db.sh"
SID=20260901_010000_test01
STATE="$PWD/scratch/wd-state"
HANDOFFS="$PWD/scratch/wd-handoffs"
PASS=0; FAIL=0

ok()   { PASS=$((PASS+1)); echo "  PASS: $1"; }
fail() { FAIL=$((FAIL+1)); echo "  FAIL: $1"; }

if ! curl -s --max-time 2 http://localhost:21143/api/tags >/dev/null 2>&1; then
  echo "SKIP: mock Ollama not running on :21143 (start: bash scripts/mock-ollama.sh 21143 &)" >&2
  exit 2
fi

export CE_WATCHDOG_DB="$PWD/scratch/fixture-big.db"
export CE_WATCHDOG_WARN_TOKENS=300
export CE_WATCHDOG_ALERT_TOKENS=600
export CE_WATCHDOG_EXTRACT_TOKENS=900
export CE_WATCHDOG_CHAR_PER_TOKEN=4
export CE_WATCHDOG_STATE_DIR="$STATE"
export CE_WATCHDOG_OUT_DIR="$HANDOFFS"
export CE_WATCHDOG_PICKUP_SCRIPT="$PICKUP"
export CE_WATCHDOG_PICKUP_MODEL="test-model"
export CE_WATCHDOG_OLLAMA_URL="http://localhost:21143/api/chat"
export CE_WATCHDOG_FRESH_SECS=100000
export CE_WATCHDOG_CRIT_DELTA_TOKENS=800

expect_out() { if [[ "$OUT" =~ $2 ]]; then ok "$1"; else fail "$1 — got: ${OUT:-<silent>}"; fi; }
expect_silent() { if [[ -z "$OUT" ]]; then ok "$1 (silent)"; else fail "$1 — got: $OUT"; fi; }

rm -rf "$STATE" "$HANDOFFS"
mkdir -p "$HANDOFFS"
mk() { bash "$FIXTURE" "$CE_WATCHDOG_DB" "$SID" "$1" >/dev/null; }

mk 200
OUT=$(CE_WATCHDOG_NOW=1788200100 bash "$WATCHDOG"); expect_silent "below floor stays silent"

mk 2000
OUT=$(CE_WATCHDOG_NOW=1788200100 bash "$WATCHDOG"); expect_out "REMIND fired at warn zone" "REMIND session $SID"
OUT=$(CE_WATCHDOG_NOW=1788200160 bash "$WATCHDOG"); expect_silent "REMIND suppressed inside hysteresis"

mk 3000
OUT=$(CE_WATCHDOG_NOW=1788200300 bash "$WATCHDOG"); expect_out "REMIND->ALERT escalation" 'ALERT session'
OUT=$(CE_WATCHDOG_NOW=1788200360 bash "$WATCHDOG"); expect_silent "ALERT suppressed inside hysteresis"

mk 4000
OUT=$(CE_WATCHDOG_NOW=1788200400 bash "$WATCHDOG"); expect_out "EXTRACT fired and produced handoff" 'EXTRACT session .*auto ce-pickup'
HANDOFF_PATH=$(printf '%s' "$OUT" | sed -n 's/.*→ //p' | head -1)
if [[ -s "${HANDOFF_PATH:-}" ]] && head -20 "$HANDOFF_PATH" | grep -q 'artifact_contract: "ce-handoff/v1"'; then
  ok "produced handoff is valid ce-handoff/v1"
else
  fail "handoff missing or invalid contract: ${HANDOFF_PATH:-none}"
fi
OUT=$(CE_WATCHDOG_NOW=1788200460 bash "$WATCHDOG"); expect_silent "post-extract state silent inside window"

mk 8000
OUT=$(CE_WATCHDOG_NOW=1788202400 bash "$WATCHDOG"); expect_out "CRIT fired after climb" 'CRIT session'
OUT=$(CE_WATCHDOG_NOW=1788202460 bash "$WATCHDOG"); expect_silent "CRIT silent on immediate repeat"

rm -rf "$STATE"
FAILSTUB="$PWD/scratch/pickup-fail.sh"
printf '#!/usr/bin/env bash\nexit 1\n' > "$FAILSTUB"
export CE_WATCHDOG_PICKUP_SCRIPT="$FAILSTUB"
mk 4000
OUT=$(CE_WATCHDOG_NOW=1788200100 bash "$WATCHDOG"); expect_out "FAIL announced when extraction fails" 'FAIL session'
OUT=$(CE_WATCHDOG_NOW=1788200160 bash "$WATCHDOG"); expect_silent "FAIL not re-announced inside alert window"
OUT=$(CE_WATCHDOG_NOW=1788202200 bash "$WATCHDOG"); expect_out "FAIL re-announced on alert cadence" 'FAIL session'
export CE_WATCHDOG_PICKUP_SCRIPT="$PICKUP"
OUT=$(CE_WATCHDOG_NOW=1788202260 bash "$WATCHDOG"); expect_out "recovery EXTRACT after pickup works again" 'EXTRACT session'
OUT=$(CE_WATCHDOG_NOW=1788202320 bash "$WATCHDOG"); expect_silent "silent after recovery extract"

mk 3000
OUT=$(CE_WATCHDOG_NOW=1788204100 bash "$WATCHDOG"); expect_silent "no re-nag in alert zone once extracted"
mk 2000
OUT=$(CE_WATCHDOG_NOW=1788204200 bash "$WATCHDOG"); expect_silent "no re-nag in warn zone after extraction"

mk 200
OUT=$(CE_WATCHDOG_NOW=1788204300 bash "$WATCHDOG"); expect_silent "silent below floor"
[[ -s "$STATE/sessions.state" ]] && [[ "$(grep -c . "$STATE/sessions.state" || true)" -gt 0 ]] \
  && fail "state not cleared" || ok "state cleared under floor"
mk 2000
OUT=$(CE_WATCHDOG_NOW=1788204400 bash "$WATCHDOG"); expect_out "fresh REMIND after state cleared" 'REMIND session'

echo
echo "RESULTS: $PASS checks ok, $FAIL failures"
[[ $FAIL -eq 0 ]] && echo "ALL SCENARIOS PASS" || { echo "SCENARIOS FAILED"; exit 1; }
