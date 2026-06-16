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
TRANSCRIPT="$(get transcript_path)"

MARK="${TMPDIR:-/tmp}/cdt-edits-${SESSION_ID:-default}.marker"
REMIND_MARK="${TMPDIR:-/tmp}/cdt-reminded-${SESSION_ID:-default}.marker"

# No edits this session → stay completely silent.
[ -f "$MARK" ] || exit 0

# Silent bookkeeping: record a session row in the DB.
CDT_HOME="$HOME/.claude"
[ -f "$CDT_HOME/bin/cdt-db.sh" ] && . "$CDT_HOME/bin/cdt-db.sh" 2>/dev/null && \
  db_session "${SESSION_ID:-unknown}" "$CWD" "stopped" 2>/dev/null

# A disabled CDT never gates or reminds (behaves as stock Claude Code).
_EN="$(grep -E '^CDT_ENABLED=' "$CDT_HOME/claude-dev-team.env" 2>/dev/null | head -1 | cut -d= -f2-)"
[ "$_EN" = "0" ] && exit 0

# --- Verification gate: edits happened — require that a test/build/lint/typecheck ran afterward. -------
# Default ON (block). Soften any time:  cdt-config verify warn|off  (writes CDT_VERIFY_GATE).
GATE="$(grep -E '^CDT_VERIFY_GATE=' "$CDT_HOME/claude-dev-team.env" 2>/dev/null | head -1 | cut -d= -f2-)"
case "$GATE" in block|warn|off) : ;; *) GATE=block ;; esac
if [ "$GATE" != "off" ]; then
  GHOOKS="$(cd "$(dirname "$0")" 2>/dev/null && pwd)"
  # shellcheck source=/dev/null
  . "$GHOOKS/verify-lib.sh" 2>/dev/null
  VMARK="$(cdt_verify_marker "${SESSION_ID:-default}" 2>/dev/null)"
  VBLOCK="${TMPDIR:-/tmp}/cdt-verify-blocked-${SESSION_ID:-default}.marker"

  unverified=1
  # Verified iff a verify-marker exists and the edit-marker is NOT newer than it (tie -> verified).
  [ -n "$VMARK" ] && [ -f "$VMARK" ] && [ ! "$MARK" -nt "$VMARK" ] && unverified=0
  # Rescue: a verifying command in the MAIN transcript that didn't trip the marker (keep false-positives low).
  if [ "$unverified" = 1 ] && [ -n "$TRANSCRIPT" ] && cdt_verify_scan_transcript "$TRANSCRIPT" 2>/dev/null; then
    unverified=0
  fi

  if [ "$unverified" = 0 ]; then
    db_event verify_gate "pass" "${SESSION_ID:-}" 2>/dev/null
  elif [ ! -f "$VBLOCK" ]; then
    : > "$VBLOCK" 2>/dev/null   # fire at most once per session — never trap the user in a loop
    if [ "$GATE" = "warn" ]; then
      db_event verify_gate "warn" "${SESSION_ID:-}" 2>/dev/null
      echo "claude-dev-team: ⚠ edits were made but no test/build/lint/typecheck command ran afterward — verify before trusting this as done (cdt-config verify off to silence)." >&2
    else
      db_event verify_gate "block" "${SESSION_ID:-}" 2>/dev/null
      printf '{"decision":"block","reason":"%s"}\n' "claude-dev-team: edits were made but no verifying command (test / build / lint / typecheck) ran afterward. Run the project's verifying command and paste its output before finishing. If a subagent already ran it, paste that output and stop again. (Soften: cdt-config verify warn|off.)"
      exit 0
    fi
  fi
fi

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
