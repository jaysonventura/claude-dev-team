#!/usr/bin/env bash
# SubagentStop hook: record which agent finished (real agent_type) to the state DB,
# so /stats can show an accurate agent-run breakdown. Fail-open: always exit 0.
set +e

INPUT="$(cat 2>/dev/null)"

# Loop guard.
printf '%s' "$INPUT" | grep -q '"stop_hook_active"[[:space:]]*:[[:space:]]*true' && exit 0

get() { printf '%s' "$INPUT" | sed -n "s/.*\"$1\"[[:space:]]*:[[:space:]]*\"\([^\"]*\)\".*/\1/p" | head -1; }
AGENT="$(get agent_type)"
[ -z "$AGENT" ] && AGENT="$(get subagent_type)"
[ -z "$AGENT" ] && AGENT="$(get agent_name)"
[ -z "$AGENT" ] && exit 0   # no identifiable agent type — skip rather than logging "unknown"
SID="$(get session_id)"

HOOKS_DIR="$(cd "$(dirname "$0")" 2>/dev/null && pwd)"
# shellcheck source=/dev/null
[ -f "$HOOKS_DIR/db.sh" ] && . "$HOOKS_DIR/db.sh" 2>/dev/null && db_agent "$AGENT" "$SID"
exit 0
