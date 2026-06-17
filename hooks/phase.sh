#!/usr/bin/env bash
# cdt-phase — record + display the orchestration phase board (the waves of a T2/T3 task). The orchestrator
# calls this at each wave boundary; it updates <cwd>/.claude/runtime/phase.json and prints the board.
# Per-phase token totals come from race-safe append-logs written by agent-track.sh (SubagentStop). The
# status line (cdt-statusline) shows a compact "phase i/N <name>" from the same state. Fail-open.
#
#   cdt-phase "<name>" [--agents a,b,c]   advance to <name>  (earlier phases -> done, this -> running)
#   cdt-phase done                        mark every phase done (ship)
#   cdt-phase show                        re-print the board
#   cdt-phase reset                       clear the board (start a new task)
#
# Toggle: cdt-config phase-board on|off  (CDT_PHASE_BOARD). Off => no-op.
set +e

CDT_HOME="$HOME/.claude"
_PB="$(grep -E '^CDT_PHASE_BOARD=' "$CDT_HOME/claude-dev-team.env" 2>/dev/null | head -1 | cut -d= -f2-)"
case "$_PB" in 0|false|off) exit 0 ;; esac
command -v python3 >/dev/null 2>&1 || exit 0

case "${1:-show}" in
  show|done|reset) CMD="$1"; NAME="" ;;
  "")              CMD="show"; NAME="" ;;
  *)               CMD="advance"; NAME="$1" ;;
esac
shift 2>/dev/null
AGENTS=""
while [ $# -gt 0 ]; do
  case "$1" in
    --agents) AGENTS="$2"; shift 2 ;;
    *) shift ;;
  esac
done

CDT_CMD="$CMD" CDT_NAME="$NAME" CDT_AGENTS="$AGENTS" CDT_ROOT="$(pwd)" python3 - <<'PY'
import os, json, time, glob

root = os.environ["CDT_ROOT"]
d = os.path.join(root, ".claude", "runtime")
pj = os.path.join(d, "phase.json")
tokdir = os.path.join(d, "phasetok")
try:
    os.makedirs(tokdir, exist_ok=True)
except Exception:
    raise SystemExit(0)

cmd = os.environ["CDT_CMD"]
name = os.environ["CDT_NAME"].strip()
agents = [a.strip() for a in os.environ["CDT_AGENTS"].split(",") if a.strip()]


def short(a):
    return (a or "").split(":")[-1].strip() or "agent"


def load():
    try:
        return json.load(open(pj))
    except Exception:
        return {"phases": [], "current": -1}


def save(s):
    s["updated"] = int(time.time())
    tmp = pj + ".%d.tmp" % os.getpid()
    json.dump(s, open(tmp, "w"))
    os.replace(tmp, pj)


s = load()
if cmd == "reset":
    save({"phases": [], "current": -1})
    for f in glob.glob(os.path.join(tokdir, "*.log")):
        try:
            os.remove(f)
        except OSError:
            pass
    raise SystemExit(0)
elif cmd == "advance":
    ph = s.setdefault("phases", [])
    idx = next((i for i, p in enumerate(ph) if p.get("name", "").lower() == name.lower()), -1)
    if idx == -1:
        ph.append({"name": name or "phase", "agents": agents})
        idx = len(ph) - 1
    elif agents:
        ph[idx]["agents"] = agents
    for i, p in enumerate(ph):
        p["status"] = "done" if i < idx else ("running" if i == idx else "queued")
    s["current"] = idx
    save(s)
elif cmd == "done":
    for p in s.get("phases", []):
        p["status"] = "done"
    s["current"] = len(s.get("phases", [])) - 1
    save(s)

ph = s.get("phases", [])
if not ph:
    raise SystemExit(0)


def toks(i):
    t = 0
    try:
        for line in open(os.path.join(tokdir, "%d.log" % i)):
            try:
                t += int(line.strip())
            except ValueError:
                pass
    except Exception:
        return 0
    return t


def fmt(n):
    if not n:
        return "—"
    if n < 1000:
        return str(n)
    if n < 1_000_000:
        return ("%.1fk" % (n / 1000)).replace(".0k", "k")
    return ("%.1fM" % (n / 1_000_000)).replace(".0M", "M")


MARK = {"done": "✓", "running": "▸", "queued": "·"}
rows = []
for i, p in enumerate(ph):
    st = p.get("status", "queued")
    ag = " · ".join(short(a) for a in (p.get("agents") or [])) or "—"
    rows.append((MARK.get(st, "·"), str(i), p.get("name", "phase"), ag, fmt(toks(i)), st))

wn = max(len(r[2]) for r in rows)
wa = max(len(r[3]) for r in rows)
wt = max(len(r[4]) for r in rows)
title = "CDT · phase board"
content = [f"{mk} {ix} {nm.ljust(wn)}  {ag.ljust(wa)}  {tk.rjust(wt)}  {st}"
           for mk, ix, nm, ag, tk, st in rows]
width = max([len(c) for c in content] + [len(title) + 2])
print("┌─ " + title + " " + "─" * (width - len(title) - 1) + "┐")
for c in content:
    print("│ " + c.ljust(width) + " │")
print("└" + "─" * (width + 2) + "┘")
PY
exit 0
