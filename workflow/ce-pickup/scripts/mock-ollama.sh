#!/usr/bin/env bash
# One-shot mock Ollama for testing ce-pickup.sh and the watchdog without a
# real model call. Pure bash + nc. Serves a static /api/chat response.
# Usage: mock-ollama.sh PORT   (foreground loop; caller backgrounds it)
set -euo pipefail
PORT="${1:-21143}"

BODY='{"message":{"role":"assistant","content":"## Objective\nVerify the synthetic fixture pipeline end to end.\n\n## Work completed\n- Fixture DB built and read through ce-pickup.\n\n## Next steps\n- Validate watchdog thresholds.\n"}}'
RESP=$(mktemp)
trap 'rm -f "$RESP"' EXIT
printf 'HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: %d\r\nConnection: close\r\n\r\n%s' \
  "${#BODY}" "$BODY" > "$RESP"

while true; do
  nc -l "$PORT" < "$RESP" >/dev/null 2>&1 || true
done
