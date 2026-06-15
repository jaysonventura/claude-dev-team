#!/usr/bin/env bash
# cdt-budget — read your latest Claude usage % (cached by the status line and/or the menu bar app) and
# recommend ECO conserve when you're running low. Fail-open: 'unavailable' if there's no fresh reading.
# Threshold via CDT_ECO_THRESHOLD (default 80% weekly).
set +e

THRESHOLD="${CDT_ECO_THRESHOLD:-80}"; case "$THRESHOLD" in ''|*[!0-9]*) THRESHOLD=80 ;; esac
CACHE="$HOME/.claude/.cdt-usage.json"

command -v python3 >/dev/null 2>&1 || { echo "cdt-budget: python3 unavailable"; exit 0; }
[ -f "$CACHE" ] || { echo "cdt-budget: usage unavailable — enable the status line (cdt-config statusline on) or run the menu bar app"; exit 0; }

THRESHOLD="$THRESHOLD" CACHE="$CACHE" python3 - <<'PY'
import os, json, time
try:
    d = json.load(open(os.environ["CACHE"]))
except Exception:
    print("cdt-budget: usage unavailable"); raise SystemExit(0)
th = int(os.environ["THRESHOLD"])
s = int(d.get("session", 0)); w = int(d.get("weekly", 0)); ts = int(d.get("ts", 0) or 0)
age = int(time.time()) - ts if ts else 10**9
stale = "  (stale — restart a session to refresh)" if age > 1800 else ""
conserve = w >= th or s >= 95
mode = "CONSERVE" if conserve else "normal"
why = f"  (weekly >= {th}%)" if (conserve and w >= th) else ("  (session >= 95%)" if conserve else "")
print(f"session {s}% · weekly {w}%  ->  ECO: {mode}{why}{stale}")
PY
exit 0
