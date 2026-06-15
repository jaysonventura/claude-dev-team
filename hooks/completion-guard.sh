#!/usr/bin/env bash
# Stop hook: when a session that made edits ends, record a session row + status digest (silent),
# and OPTIONALLY remind once to run the completion mandate (opt-in, off by default to stay cheap).
# Loop-guarded via stop_hook_active. Fail-open: always exits cleanly.
set +e

INPUT="$(cat 2>/dev/null)"

# Loop guard: if this stop was itself triggered by a stop hook, do nothing.
printf '%s' "$INPUT" | grep -q '"stop_hook_active"[[:space:]]*:[[:space:]]*true' && exit 0

get() { printf '%s' "$INPUT" | sed -n "s/.*\"$1\"[[:space:]]*:[[:space:]]*\"\([^\"]*\)\".*/\1/p" | head -1; }
SESSION_ID="$(get session_id)"
CWD="$(get cwd)"; [ -z "$CWD" ] && CWD="$PWD"

MARK="${TMPDIR:-/tmp}/cdt-edits-${SESSION_ID:-default}.marker"
REMIND_MARK="${TMPDIR:-/tmp}/cdt-reminded-${SESSION_ID:-default}.marker"

# No edits this session → stay completely silent.
[ -f "$MARK" ] || exit 0

# Silent bookkeeping: record a session row in the DB.
CDT_HOME="$HOME/.claude"
[ -f "$CDT_HOME/bin/cdt-db.sh" ] && . "$CDT_HOME/bin/cdt-db.sh" 2>/dev/null && \
  db_session "${SESSION_ID:-unknown}" "$CWD" "stopped" 2>/dev/null

# Optional mandate reminder — opt in with CDT_STOP_REMINDER=1 (kept off by default for cost).
# Read just this key (don't `source` the env file — a crafted value must never execute).
_REMIND="$(grep -E '^CDT_STOP_REMINDER=' "$CDT_HOME/claude-dev-team.env" 2>/dev/null | head -1 | cut -d= -f2-)"
if [ "${_REMIND:-0}" = "1" ] && [ ! -f "$REMIND_MARK" ]; then
  : > "$REMIND_MARK" 2>/dev/null
  printf '{"decision":"block","reason":"%s"}\n' \
    "claude-dev-team: edits were made — run the completion mandate before finishing (simplify, code-review, reuse-audit, dead-code scan, verify with command output, persist a vault learning), then post a SHIP digest via cdt-notify. If already done, you may stop."
  exit 0
fi
exit 0
