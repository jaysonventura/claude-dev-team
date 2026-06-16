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

# Sum this subagent's REAL token usage from its transcript JSONL (no token field is in the hook payload).
# Split into TOKENS = cost-relevant (input + output + cache_creation) and CACHE_READ = the discounted
# cache-hit reads — kept apart so cheap cache reads (which can be ~100x the fresh count for a subagent)
# don't dominate the per-agent cost ranking. Grounded in actual usage rows. Fail-open: 0/0 if unreadable.
TOKENS=0; CACHE_READ=0
if [ -n "$TRANSCRIPT" ] && [ -f "$TRANSCRIPT" ] && command -v python3 >/dev/null 2>&1; then
  read -r TOKENS CACHE_READ <<EOF2
$(CDT_TRANSCRIPT="$TRANSCRIPT" python3 -c 'import os,json
f=0; c=0
try:
    with open(os.environ["CDT_TRANSCRIPT"],encoding="utf-8",errors="ignore") as fh:
        for line in fh:
            line=line.strip()
            if not line: continue
            try: o=json.loads(line)
            except Exception: continue
            u=(o.get("message") or {}).get("usage") or {}
            for k in ("input_tokens","output_tokens","cache_creation_input_tokens"):
                v=u.get(k)
                if isinstance(v,int): f+=v
            cr=u.get("cache_read_input_tokens")
            if isinstance(cr,int): c+=cr
    print(f, c)
except Exception: print(0, 0)' 2>/dev/null)
EOF2
  case "$TOKENS" in ''|*[!0-9]*) TOKENS=0 ;; esac
  case "$CACHE_READ" in ''|*[!0-9]*) CACHE_READ=0 ;; esac
fi

HOOKS_DIR="$(cd "$(dirname "$0")" 2>/dev/null && pwd)"
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
exit 0
