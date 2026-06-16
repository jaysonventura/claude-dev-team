#!/usr/bin/env bash
# PreToolUse (Task) hook: when the orchestrator dispatches a specialist, capture its exclusive-file
# contract so the SubagentStop hook can later check what the agent actually touched. The orchestrator
# emits one machine-readable line in the dispatch prompt:
#     CDT-CONTRACT: exclusive=api/**,server/** ; read=types/**
# We never block dispatch — this is pure bookkeeping. Fail-open: always exit 0.
set +e

INPUT="$(cat 2>/dev/null)"
CDT_HOME="$HOME/.claude"
_EN="$(grep -E '^CDT_ENABLED=' "$CDT_HOME/claude-dev-team.env" 2>/dev/null | head -1 | cut -d= -f2-)"
[ "$_EN" = "0" ] && exit 0
command -v python3 >/dev/null 2>&1 || exit 0

CDT_PAYLOAD="$INPUT" CDT_DIR="$CDT_HOME/.cdt/contracts" python3 - <<'PY'
import os, json, re, time
try:
    o = json.loads(os.environ.get("CDT_PAYLOAD", "") or "{}")
except Exception:
    raise SystemExit(0)
if (o.get("tool_name") or "") != "Task":
    raise SystemExit(0)
ti = o.get("tool_input") or {}
agent = ti.get("subagent_type") or ""
prompt = ti.get("prompt") or ""
sid = o.get("session_id") or "default"
cwd = o.get("cwd") or ""
m = re.search(r"CDT-CONTRACT:\s*(.+)", prompt)
if not m or not agent:
    raise SystemExit(0)
spec = m.group(1).strip().splitlines()[0]
excl, read = [], []
for part in spec.split(";"):
    if "=" not in part:
        continue
    k, v = part.split("=", 1)
    vals = [x.strip() for x in v.split(",") if x.strip()]
    if k.strip().lower() == "exclusive":
        excl = vals
    elif k.strip().lower() == "read":
        read = vals
if not excl:
    raise SystemExit(0)
base = os.path.join(os.environ["CDT_DIR"], sid, "pending")
try:
    os.makedirs(base, exist_ok=True)
    seq = "%d-%d" % (int(time.time() * 1e9), os.getpid())   # sortable + unique under parallel dispatch
    san = re.sub(r"[/:]+", "-", agent)
    fn = os.path.join(base, "%s__%s.json" % (seq, san))
    json.dump({"seq": seq, "session_id": sid, "agent_type": agent, "exclusive": excl,
               "read": read, "cwd": cwd, "created": seq}, open(fn, "w"))
except Exception:
    pass
PY
exit 0
