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

# Sum this subagent's REAL token usage from its transcript JSONL (no token field is in the hook
# payload). Each assistant line carries message.usage{input,output,cache_*}; total = their sum.
# Grounded in actual usage rows — never an estimate. Fail-open: 0 if no python3 / unreadable.
TOKENS=0
if [ -n "$TRANSCRIPT" ] && [ -f "$TRANSCRIPT" ] && command -v python3 >/dev/null 2>&1; then
  TOKENS="$(CDT_TRANSCRIPT="$TRANSCRIPT" python3 -c 'import os,json
t=0
try:
    with open(os.environ["CDT_TRANSCRIPT"],encoding="utf-8",errors="ignore") as f:
        for line in f:
            line=line.strip()
            if not line: continue
            try: o=json.loads(line)
            except Exception: continue
            u=(o.get("message") or {}).get("usage") or {}
            for k in ("input_tokens","output_tokens","cache_creation_input_tokens","cache_read_input_tokens"):
                v=u.get(k)
                if isinstance(v,int): t+=v
    print(t)
except Exception: print(0)' 2>/dev/null)"
  case "$TOKENS" in ''|*[!0-9]*) TOKENS=0 ;; esac
fi

HOOKS_DIR="$(cd "$(dirname "$0")" 2>/dev/null && pwd)"
# shellcheck source=/dev/null
[ -f "$HOOKS_DIR/db.sh" ] && . "$HOOKS_DIR/db.sh" 2>/dev/null && db_agent "$AGENT" "$SID" "$TOKENS"
exit 0
