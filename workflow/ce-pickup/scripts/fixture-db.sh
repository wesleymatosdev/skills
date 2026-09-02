#!/usr/bin/env bash
# Build a synthetic Hermes state.db fixture for testing ce-pickup and the
# context-ceiling watchdog. sqlite3 only — no Python, no TCC prompts.
#
# Usage: fixture-db.sh OUT_PATH [SESSION_ID] [TOTAL_CONTENT_CHARS]
# Schema mirrors the state.db columns the watchdog/ce-pickup read.
set -euo pipefail

FIXTURE="${1:?usage: fixture-db.sh OUT_PATH [SESSION_ID] [TOTAL_CONTENT_CHARS]}"
SID="${2:-20260901_010000_test01}"
TOTAL_CHARS="${3:-400}"

rm -f "$FIXTURE"
sqlite3 "$FIXTURE" <<SQL
CREATE TABLE sessions (
  id TEXT PRIMARY KEY, source TEXT, display_name TEXT, title TEXT,
  started_at REAL, ended_at REAL, end_reason TEXT, cwd TEXT,
  git_branch TEXT, git_repo_root TEXT, archived INTEGER DEFAULT 0,
  hidden INTEGER DEFAULT 0, message_count INTEGER DEFAULT 0,
  last_activity_at REAL
);
CREATE TABLE messages (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  session_id TEXT NOT NULL,
  role TEXT NOT NULL,
  content TEXT,
  tool_name TEXT,
  timestamp REAL NOT NULL,
  active INTEGER NOT NULL DEFAULT 1
);
INSERT INTO sessions VALUES
  ('${SID}','cli','Synthetic context-ceiling fixture','Synthetic context-ceiling fixture',
   1788200000.0,NULL,NULL,'/tmp/synthetic-proj','main','/tmp/synthetic-proj',0,0,0,
   1788200003.0);
INSERT INTO messages (session_id, role, content, tool_name, timestamp, active) VALUES
  ('${SID}','user','Objective: verify the synthetic fixture pipeline end to end. Padding follows.',NULL,1788200001,1),
  ('${SID}','tool','[synthetic tool output for extraction]','read_file',1788200002,1),
  ('${SID}','assistant','Work completed: fixture built; watchdog thresholds to be verified against this session.',NULL,1788200003,1);
SQL

# Pad the tool message so total content length ≈ TOTAL_CHARS.
# Base lengths: user 77 + assistant 87 + prefix 'synthetic padding token ' (24) = 188.
if (( TOTAL_CHARS > 600 )); then
  PAD_FILE=$(mktemp)
  {
    printf 'synthetic padding token '
    awk -v n="$(( TOTAL_CHARS - 188 ))" 'BEGIN { for (i=0;i<n;i++) printf "x"}'
    printf '\n'
  } > "$PAD_FILE"
  PAD="$(cat "$PAD_FILE")"
  rm -f "$PAD_FILE"
  sqlite3 "$FIXTURE" "UPDATE messages SET content = content || '${PAD}' WHERE role='tool';"
fi

echo "fixture: $FIXTURE (session ${SID}, ~${TOTAL_CHARS} chars)"
