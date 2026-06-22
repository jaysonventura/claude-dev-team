#!/usr/bin/env bash
# cdt-statusline — Claude Code status line for claude-dev-team. Reads the session JSON on stdin and prints
# a minimal line: CDT on/off · model · current-session usage % · weekly usage %. Plain text, no emoji.
# Also caches session+weekly % to ~/.claude/.cdt-usage.json so cdt-budget / Eco mode can read them
# (cross-platform, no Keychain/curl). Enable with: cdt-config statusline on.
set +e

IN="$(cat 2>/dev/null)"
CDT_HOME="$HOME/.claude"
EN="$(grep -E '^CDT_ENABLED=' "$CDT_HOME/claude-dev-team.env" 2>/dev/null | head -1 | cut -d= -f2-)"
MODE="$([ "$EN" = "0" ] && echo OFF || echo on)"

command -v python3 >/dev/null 2>&1 || { echo "CDT $MODE"; exit 0; }

IN="$IN" MODE="$MODE" CACHE="$CDT_HOME/.cdt-usage.json" python3 - <<'PY' 2>/dev/null
import os, json, time

cache = os.environ["CACHE"]
try:
    d = json.loads(os.environ.get("IN", "") or "{}")
except Exception:
    d = {}

model = (d.get("model") or {}).get("display_name") or "?"
rl = d.get("rate_limits") or {}
def up(k):
    try:
        return round(float((rl.get(k) or {}).get("used_percentage", 0)))
    except Exception:
        return None
wk = up("seven_day"); se = up("five_hour")    # weekly (7-day) + current session (5-hour) used %

# Persist session+weekly % so cdt-budget / Eco mode can read them (display-only cache, atomic write).
if wk is not None or se is not None:
    try:
        ex = {}
        try:
            ex = json.load(open(cache))
        except Exception:
            pass
        ex.update({"session": se or 0, "weekly": wk or 0, "ts": int(time.time())})
        tmp = cache + ".%d.tmp" % os.getpid()
        with open(tmp, "w") as f:
            json.dump(ex, f)
        os.replace(tmp, cache)
    except Exception:
        pass

# Display-only line: CDT on · <model> · <session>% session · <weekly>% weekly. No emoji.
parts = ["CDT %s" % os.environ["MODE"], model]
if se is not None:
    parts.append("%d%% session" % se)
if wk is not None:
    parts.append("%d%% weekly" % wk)
print(" · ".join(parts))
PY
exit 0
