#!/usr/bin/env bash
# usage-lib.sh — shared transcript token accounting. Sourced by agent-track.sh (per-subagent cost) and
# completion-guard.sh (orchestrator overhead). Echoes "<fresh> <cache_read>" where fresh = cost-relevant
# tokens (input + output + cache_creation) and cache_read = the discounted cache-hit reads (kept apart so
# they can't swamp the cost figure). Prints "0 0" on any error. Fail-open.
cdt_usage_tokens() {
  local tp="$1"
  { [ -n "$tp" ] && [ -f "$tp" ] && command -v python3 >/dev/null 2>&1; } || { echo "0 0"; return 0; }
  CDT_TP="$tp" python3 - <<'PY'
import os, json
f = c = 0
try:
    with open(os.environ["CDT_TP"], encoding="utf-8", errors="ignore") as fh:
        for line in fh:
            line = line.strip()
            if not line:
                continue
            try:
                o = json.loads(line)
            except Exception:
                continue
            u = (o.get("message") or {}).get("usage") or {}
            for k in ("input_tokens", "output_tokens", "cache_creation_input_tokens"):
                v = u.get(k)
                if isinstance(v, int):
                    f += v
            cr = u.get("cache_read_input_tokens")
            if isinstance(cr, int):
                c += cr
    print(f, c)
except Exception:
    print(0, 0)
PY
}
