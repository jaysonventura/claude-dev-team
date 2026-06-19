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
HD="$(cd "$(dirname "$0")" 2>/dev/null && pwd)"   # cdt_emoji.py + running_agents.py live beside this script

IN="$IN" MODE="$MODE" PB="$PB" HOOKS_DIR="$HD" CACHE="$CDT_HOME/.cdt-usage.json" python3 - <<'PY' 2>/dev/null
import os, json, time, re, sys

# Shared emoji map + the live running-agents segment. Fail-soft: if the helpers aren't beside this script
# (older/partial install), the line still renders, just without emoji / the running segment.
sys.path.insert(0, os.environ.get("HOOKS_DIR", ""))
try:
    import running_agents as _run
except Exception:
    _run = None
try:
    import usage_cache as _uc
except Exception:
    _uc = None

home = os.path.expanduser("~/.claude")
cache = os.environ["CACHE"]

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

# Per-session health metrics (context size, session age, subagents) are keyed by WORKSPACE so two terminals
# in different projects don't clobber each other; account-wide session/weekly % stay global (top-level).
ws = (d.get("workspace") or {}).get("current_dir") or d.get("cwd") or ""
sess = _uc.get_session(_uc.skey(ws)) if _uc else {}

# --- Context tokens: scan current project's JSONL (mtime-guarded to skip re-reads) ---
ctx_tokens = sess.get("ctx_tokens", 0)
ctx_mtime  = sess.get("ctx_mtime", 0.0)
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

# --- Session duration (this session's own start, set by SessionStart) ---
session_start = sess.get("session_start", 0)
dur_str = None
if session_start > 0:
    elapsed = int(time.time()) - session_start
    dur_str = f"{elapsed // 3600}h" if elapsed >= 3600 else f"{elapsed // 60}m"

# Persist: account-wide usage % (top-level, shared across terminals) + THIS session's context size.
if wk is not None or se is not None:
    glob = {"session": se or 0, "weekly": wk or 0, "ts": int(time.time())}
    if _uc:
        try:
            _uc.update_ctx(_uc.skey(ws), ctx_tokens, ctx_mtime, glob)
        except Exception:
            pass
    else:                                   # legacy fallback (helper missing): keep usage % fresh globally
        try:
            ex = {}
            try:
                ex = json.load(open(cache))
            except Exception:
                pass
            ex.update(glob)
            tmp_f = cache + ".%d.tmp" % os.getpid()
            with open(tmp_f, "w") as f:
                json.dump(ex, f)
            os.replace(tmp_f, cache)
        except Exception:
            pass

parts = [f"CDT {os.environ['MODE']}", f"🧠 {model}"]
if effort:
    parts.append(f"⚡ {effort}")
if wk is not None:
    parts.append(f"📊 {wk}% wk")

# Health metrics: context size, session age.
agent_count = sess.get("agent_count", 0)
if ctx_tokens > 0:
    parts.append(f"🪟 {ctx_tokens // 1000}k" if ctx_tokens >= 1000 else f"🪟 {ctx_tokens}")
if dur_str:
    parts.append(f"⏱ {dur_str}")

# Per-agent: show what's running NOW (live, e.g. "🔭 Explore×3") when a wave is in flight; otherwise the
# cumulative subagents-this-session count. The live segment is what makes the auto-mode display useful.
run_seg = ""
if _run is not None and ws:
    try:
        run_seg = _run.render(ws)
    except Exception:
        run_seg = ""
parts.append(run_seg if run_seg else f"🤖 {agent_count}")

# Phase indicator (if enabled, a board is active for this workspace, and fresh): "🧭 2/4 Build".
if os.environ.get("PB", "").lower() not in ("0", "false", "off"):
    try:
        pjf = os.path.join(ws, ".claude", "runtime", "phase.json") if ws else ""
        if pjf and os.path.exists(pjf) and (time.time() - os.path.getmtime(pjf) < 3600):
            ps = json.load(open(pjf)); cur = ps.get("current", -1); phs = ps.get("phases") or []
            if 0 <= cur < len(phs):
                parts.append("🧭 %d/%d %s" % (cur + 1, len(phs), phs[cur].get("name", "")))
    except Exception:
        pass
print(" · ".join(parts))
PY
exit 0
