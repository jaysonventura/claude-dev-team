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
import os, json, time, re

home = os.path.expanduser("~/.claude")
cache = os.environ["CACHE"]

try:
    d = json.loads(os.environ.get("IN", "") or "{}")
except Exception:
    d = {}

# Read existing cache to preserve session_start + agent_count written by other hooks.
existing = {}
try:
    existing = json.load(open(cache))
except Exception:
    pass

model = (d.get("model") or {}).get("display_name") or "?"
effort = (d.get("effort") or {}).get("level") or ""
rl = d.get("rate_limits") or {}
def up(k):
    try:
        return round(float((rl.get(k) or {}).get("used_percentage", 0)))
    except Exception:
        return None
wk = up("seven_day"); se = up("five_hour")

# --- Context tokens: scan current project's JSONL (mtime-guarded to skip re-reads) ---
ws = (d.get("workspace") or {}).get("current_dir") or d.get("cwd") or ""
ctx_tokens = existing.get("ctx_tokens", 0)
ctx_mtime  = existing.get("ctx_mtime", 0.0)
if ws:
    encoded  = ws.replace("/", "-")          # /Users/foo/bar → -Users-foo-bar
    proj_dir = os.path.join(home, "projects", encoded)
    if os.path.isdir(proj_dir):
        jsonls = [os.path.join(proj_dir, f) for f in os.listdir(proj_dir) if f.endswith(".jsonl")]
        if jsonls:
            newest = max(jsonls, key=os.path.getmtime)
            mtime  = os.path.getmtime(newest)
            if mtime > ctx_mtime:
                try:
                    sz = os.path.getsize(newest)
                    with open(newest, "rb") as fh:
                        fh.seek(max(0, sz - 8192))
                        tail = fh.read().decode("utf-8", errors="ignore")
                    m = re.findall(r'"input_tokens"\s*:\s*(\d+)', tail)
                    if m:
                        ctx_tokens = int(m[-1])
                        ctx_mtime  = mtime
                except Exception:
                    pass

# --- Session duration ---
session_start = existing.get("session_start", 0)
dur_str = None
if session_start > 0:
    elapsed = int(time.time()) - session_start
    dur_str = f"{elapsed // 3600}h" if elapsed >= 3600 else f"{elapsed // 60}m"

# Merge-write cache: update rate-limit % and context fields, preserve session_start + agent_count.
if wk is not None or se is not None:
    try:
        existing.update({"session": se or 0, "weekly": wk or 0, "ts": int(time.time()),
                         "ctx_tokens": ctx_tokens, "ctx_mtime": ctx_mtime})
        tmp_f = cache + ".%d.tmp" % os.getpid()
        with open(tmp_f, "w") as f:
            json.dump(existing, f)
        os.replace(tmp_f, cache)
    except Exception:
        pass

parts = [f"CDT {os.environ['MODE']}", model]
if effort:
    parts.append(effort)
if wk is not None:
    parts.append(f"{wk}% wk")

# Health metrics: context size, session age, subagent count.
agent_count = existing.get("agent_count", 0)
if ctx_tokens > 0:
    parts.append(f"{ctx_tokens // 1000}k" if ctx_tokens >= 1000 else str(ctx_tokens))
if dur_str:
    parts.append(dur_str)
parts.append(f"{agent_count}⪟")

# Phase board indicator (if enabled, a board is active for this workspace, and fresh): "phase 2/4 Build".
if os.environ.get("PB", "").lower() not in ("0", "false", "off"):
    try:
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
