#!/usr/bin/env bash
# cdt-statusline — Claude Code status line for claude-dev-team. Reads the session JSON on stdin and
# prints a compact line: CDT mode · model · effort · weekly usage %. Also caches the usage % to
# ~/.claude/.cdt-usage.json so cdt-budget / Eco mode can read it (cross-platform, no Keychain/curl).
# Enable with: cdt-config statusline on   (writes the statusLine setting to settings.json).
set +e

IN="$(cat 2>/dev/null)"
CDT_HOME="$HOME/.claude"
EN="$(grep -E '^CDT_ENABLED=' "$CDT_HOME/claude-dev-team.env" 2>/dev/null | head -1 | cut -d= -f2-)"
MODE="$([ "$EN" = "0" ] && echo OFF || echo on)"
PB="$(grep -E '^CDT_PHASE_BOARD=' "$CDT_HOME/claude-dev-team.env" 2>/dev/null | head -1 | cut -d= -f2-)"

command -v python3 >/dev/null 2>&1 || { echo "CDT $MODE"; exit 0; }

IN="$IN" MODE="$MODE" PB="$PB" CACHE="$CDT_HOME/.cdt-usage.json" python3 - <<'PY' 2>/dev/null
import os, json, time
try:
    d = json.loads(os.environ.get("IN", "") or "{}")
except Exception:
    d = {}
model = (d.get("model") or {}).get("display_name") or "?"
effort = (d.get("effort") or {}).get("level") or ""
rl = d.get("rate_limits") or {}
def up(k):
    try:
        return round(float((rl.get(k) or {}).get("used_percentage", 0)))
    except Exception:
        return None
wk = up("seven_day"); se = up("five_hour")
# Cache the usage for cdt-budget / Eco mode. Write atomically (temp + replace) so a concurrent
# statusline render can't read a half-written file.
if wk is not None or se is not None:
    try:
        cache = os.environ["CACHE"]; tmp = cache + ".%d.tmp" % os.getpid()
        with open(tmp, "w") as f:
            json.dump({"session": se or 0, "weekly": wk or 0, "ts": int(time.time())}, f)
        os.replace(tmp, cache)
    except Exception:
        pass
parts = [f"CDT {os.environ['MODE']}", model]
if effort:
    parts.append(effort)
if wk is not None:
    parts.append(f"{wk}% wk")
# Phase board indicator (if enabled, a board is active for this workspace, and fresh): "phase 2/4 Build".
if os.environ.get("PB", "").lower() not in ("0", "false", "off"):
    try:
        ws = (d.get("workspace") or {}).get("current_dir") or d.get("cwd") or ""
        pjf = os.path.join(ws, ".claude", "runtime", "phase.json") if ws else ""
        if pjf and os.path.exists(pjf) and (time.time() - os.path.getmtime(pjf) < 3600):
            ps = json.load(open(pjf)); cur = ps.get("current", -1); phs = ps.get("phases") or []
            if 0 <= cur < len(phs):
                parts.append("phase %d/%d %s" % (cur + 1, len(phs), phs[cur].get("name", "")))
    except Exception:
        pass
print(" · ".join(parts))
PY
exit 0
