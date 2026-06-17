#!/usr/bin/env bash
# PostToolUse (Bash) hook: when a verifying command (test / build / lint / typecheck) runs, mark this
# session "verified" so the Stop verification gate (completion-guard.sh) knows real verification happened
# after the edits. Symmetric with format-on-write.sh's edit marker (same PostToolUse channel).
# Fail-open: always exit 0.
set +e

INPUT="$(cat 2>/dev/null)"

# Loop guard (harmless for PostToolUse, but cheap and consistent with the other hooks).
printf '%s' "$INPUT" | grep -q '"stop_hook_active"[[:space:]]*:[[:space:]]*true' && exit 0

get() { printf '%s' "$INPUT" | sed -n "s/.*\"$1\"[[:space:]]*:[[:space:]]*\"\([^\"]*\)\".*/\1/p" | head -1; }
SESSION_ID="$(get session_id)"

CDT_HOME="$HOME/.claude"
# Honor the global off switch — never do bookkeeping for a disabled CDT.
_EN="$(grep -E '^CDT_ENABLED=' "$CDT_HOME/claude-dev-team.env" 2>/dev/null | head -1 | cut -d= -f2-)"
[ "$_EN" = "0" ] && exit 0
_RO="$(grep -E '^CDT_VERIFY_REQUIRE_OUTPUT=' "$CDT_HOME/claude-dev-team.env" 2>/dev/null | head -1 | cut -d= -f2-)"
case "$_RO" in 0|1) : ;; *) _RO=1 ;; esac

HOOKS_DIR="$(cd "$(dirname "$0")" 2>/dev/null && pwd)"
# shellcheck source=/dev/null
. "$HOOKS_DIR/verify-lib.sh" 2>/dev/null || exit 0

MARK="$(cdt_verify_marker "${SESSION_ID:-default}")"

MATCHED=0
if command -v python3 >/dev/null 2>&1; then
  export CDT_PAYLOAD="$INPUT" CDT_REQUIRE_OUTPUT="$_RO"
  cdt_verify_payload_mark && { : > "$MARK" 2>/dev/null; MATCHED=1; }
  unset CDT_PAYLOAD CDT_REQUIRE_OUTPUT
else
  # No python3: best-effort extract of the command (truncates at the first quote, fine for a leading verb).
  CMD="$(get command)"
  cdt_verify_match "$CMD" && { : > "$MARK" 2>/dev/null; MATCHED=1; }
fi

# claude-dev-team-toolkit: best-effort verify event. exitCode is UNRELIABLE from the PostToolUse payload
# (tool_response shape is undocumented), so we record exitCode:null, source:"hook" — which can NEVER produce
# verification:passed. Trusted 'passed' comes only from `cdt-verify -- <cmd>`. Append is O_APPEND (atomic).
if [ "$MATCHED" = 1 ]; then
  _CWD="$(get cwd)"; [ -z "$_CWD" ] && _CWD="$PWD"
  _CMD="${CMD:-$(get command)}"
  _EVDIR="$_CWD/.claude/runtime"
  if mkdir -p "$_EVDIR" 2>/dev/null && command -v python3 >/dev/null 2>&1; then
    CDT_CMD="$_CMD" CDT_CWD="$_CWD" python3 - >> "$_EVDIR/verify-events.jsonl" 2>/dev/null <<'PYE' || true
import os, json, datetime
print(json.dumps({
  "ts": datetime.datetime.utcnow().strftime("%Y-%m-%dT%H:%M:%SZ"),
  "command": os.environ.get("CDT_CMD", "")[:500],
  "type": "other",
  "exitCode": None,
  "cwd": os.environ.get("CDT_CWD", ""),
  "source": "hook",
}))
PYE
  fi
fi
exit 0
