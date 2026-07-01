#!/usr/bin/env bash
# cdt-budget — read your latest Claude usage % (cached by the status line and/or the menu bar app) and
# recommend ECO conserve when you're running low. Fail-open: 'unavailable' if there's no fresh reading.
# Threshold via CDT_ECO_THRESHOLD (default 80% weekly).
set +e

THRESHOLD="${CDT_ECO_THRESHOLD:-80}"; case "$THRESHOLD" in ''|*[!0-9]*) THRESHOLD=80 ;; esac
CACHE="$HOME/.claude/.cdt-usage.json"
ENV_FILE="${CDT_ENV_FILE:-$HOME/.claude/claude-dev-team.env}"
RT="${CDT_REALTIME_USAGE:-$(grep -E '^CDT_REALTIME_USAGE=' "$ENV_FILE" 2>/dev/null | head -1 | cut -d= -f2-)}"

command -v python3 >/dev/null 2>&1 || { echo "cdt-budget: python3 unavailable"; exit 0; }
[ -f "$CACHE" ] || { echo "cdt-budget: usage unavailable — enable the status line (cdt-config statusline on), then run claude in a terminal once to populate it (VS Code/JetBrains: the integrated terminal)"; exit 0; }

THRESHOLD="$THRESHOLD" CACHE="$CACHE" RT="$RT" python3 - <<'PY'
import os, json, time
try:
    d = json.load(open(os.environ["CACHE"]))
except Exception:
    print("cdt-budget: usage unavailable"); raise SystemExit(0)
th = int(os.environ["THRESHOLD"])
s = int(d.get("session", 0)); w = int(d.get("weekly", 0)); ts = int(d.get("ts", 0) or 0)
age = int(time.time()) - ts if ts else 10**9
stale = "  (stale — refresh by running claude in any terminal; VS Code/JetBrains: the integrated terminal)" if age > 1800 else ""
if age > 1800 and os.environ.get("RT", "") != "1": stale += "  or enable realtime: cdt-config realtime-usage on"
conserve = w >= th or s >= 95
mode = "CONSERVE" if conserve else "normal"
why = f"  (weekly >= {th}%)" if (conserve and w >= th) else ("  (session >= 95%)" if conserve else "")
print(f"session {s}% · weekly {w}%  ->  ECO: {mode}{why}{stale}")
PY
exit 0
