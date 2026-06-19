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
TRANSCRIPT="$(get transcript_path)"

HOOKS_DIR="$(cd "$(dirname "$0")" 2>/dev/null && pwd)"

# Sum this subagent's REAL token usage from its transcript JSONL (no token field is in the hook payload):
# TOKENS = cost-relevant (input + output + cache_creation), CACHE_READ = discounted cache-hit reads (kept
# apart so cheap cache reads — ~100x the fresh count for a subagent — don't dominate the cost ranking).
# Shared with the orchestrator-overhead meter (usage-lib.sh). Fail-open: 0/0 if unreadable.
TOKENS=0; CACHE_READ=0
# shellcheck source=/dev/null
. "$HOOKS_DIR/usage-lib.sh" 2>/dev/null
if [ -n "$TRANSCRIPT" ]; then
  read -r TOKENS CACHE_READ <<EOF2
$(cdt_usage_tokens "$TRANSCRIPT")
EOF2
  case "$TOKENS" in ''|*[!0-9]*) TOKENS=0 ;; esac
  case "$CACHE_READ" in ''|*[!0-9]*) CACHE_READ=0 ;; esac
fi

# Pretty agent-activity finish line: "✅ <emoji> <agent> · <N> tok" as the agent completes. Display-only
# (hook systemMessage → shown to the user, never added to the model context) → ZERO token cost. The token
# count is the same value already summed above for /cdt:stats. Gated by CDT_AGENT_ACTIVITY (on|compact|off).
CDT_EVENT=stop CDT_AGENT="$AGENT" CDT_TOKENS="$TOKENS" CDT_HOME="$HOME/.claude" \
  python3 "$HOOKS_DIR/agent_activity.py" 2>/dev/null

# Phase board: append this agent's tokens to the CURRENT phase's race-safe token log (append-only → safe
# under parallel SubagentStop). Only when a board is active for this workspace. cwd from the hook payload.
_PCWD="$(get cwd)"
if [ -n "$_PCWD" ] && [ -f "$_PCWD/.claude/runtime/phase.json" ]; then
  _PCUR="$(python3 -c "import json,sys;print(json.load(open(sys.argv[1])).get('current',-1))" "$_PCWD/.claude/runtime/phase.json" 2>/dev/null)"
  case "$_PCUR" in ''|*[!0-9]*) _PCUR="" ;; esac
  [ -n "$_PCUR" ] && { mkdir -p "$_PCWD/.claude/runtime/phasetok" 2>/dev/null; printf '%s\n' "$TOKENS" >> "$_PCWD/.claude/runtime/phasetok/$_PCUR.log"; }
fi

# Remove this agent from the live running-agents set (status-line "running now" segment). Fail-open.
_RCWD="$(get cwd)"
[ -n "$_RCWD" ] && CDT_WS="$_RCWD" python3 "$HOOKS_DIR/running_agents.py" remove "$AGENT" 2>/dev/null

# shellcheck source=/dev/null
[ -f "$HOOKS_DIR/db.sh" ] && . "$HOOKS_DIR/db.sh" 2>/dev/null && db_agent "$AGENT" "$SID" "$TOKENS" "$CACHE_READ"

# If this subagent ran a verifying command (e.g. qa-engineer's test/build), mark the session "verified"
# so the Stop verification gate doesn't false-positive on the team-tier flow where the tests run inside a
# subagent (whose commands never reach the main session's PostToolUse channel). Fail-open.
if [ -n "$SID" ] && [ -n "$TRANSCRIPT" ] && [ -f "$TRANSCRIPT" ]; then
  # shellcheck source=/dev/null
  . "$HOOKS_DIR/verify-lib.sh" 2>/dev/null \
    && cdt_verify_scan_transcript "$TRANSCRIPT" \
    && : > "$(cdt_verify_marker "$SID")" 2>/dev/null
fi

# Scope/sprawl detection (Phase 3): claim this subagent's exclusive-file contract and flag any file it
# wrote outside that contract (overreach) or into a peer's scope (collision). Fail-open — no contract,
# no python3, or no transcript simply records nothing.
if [ -n "$SID" ] && [ -f "$HOOKS_DIR/scope-lib.sh" ]; then
  # shellcheck source=/dev/null
  . "$HOOKS_DIR/scope-lib.sh" 2>/dev/null
  _OWN="$(cdt_scope_claim "$SID" "$AGENT" 2>/dev/null)"
  if [ -n "$_OWN" ]; then
    _SDIR="$(cdt_scope_dir "$SID")"
    _CWD="$(get cwd)"
    export CDT_TRANSCRIPT="$TRANSCRIPT" CDT_OWN="$_OWN" CDT_SESSION_DIR="$_SDIR" CDT_AGENT="$AGENT" CDT_CWD="$_CWD"
    _FIND="$(cdt_scope_eval 2>/dev/null)"
    unset CDT_TRANSCRIPT CDT_OWN CDT_SESSION_DIR CDT_AGENT CDT_CWD
    if [ -n "$_FIND" ]; then
      printf '%s\n' "$_FIND" >> "$_SDIR/findings.jsonl" 2>/dev/null
      _NO="$(printf '%s' "$_FIND" | grep -c 'overreach')"
      _NC="$(printf '%s' "$_FIND" | grep -c 'collision')"
      [ "${_NO:-0}" -gt 0 ] && db_event scope_overreach "$AGENT wrote $_NO file(s) outside its contract" "$SID" 2>/dev/null
      [ "${_NC:-0}" -gt 0 ] && db_event scope_collision "$AGENT wrote $_NC file(s) in a peer's scope" "$SID" 2>/dev/null
    fi
  else
    db_event scope "no contract matched for $AGENT" "$SID" 2>/dev/null
  fi
fi

# Increment THIS session's subagent count (per-workspace, for the status-line health display). Keyed by
# workspace so two terminals in different projects keep separate counts. Fail-open.
python3 "$HOOKS_DIR/usage_cache.py" incr "$_RCWD" 2>/dev/null
exit 0
