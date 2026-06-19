#!/usr/bin/env python3
"""Live "running subagents" tracker for claude-dev-team's status-line segment.

A tiny per-workspace set of the subagents currently in flight, so the status line can show what's running
NOW (e.g. "🔭 Explore×3") instead of only a cumulative session count. Maintained by two display hooks:
  contract-capture.sh (PreToolUse[Task]) → `add`    (a dispatch starts an agent)
  agent-track.sh      (SubagentStop)      → `remove` (that agent finished)
State: <workspace>/.claude/runtime/running-agents.json — git-ignored, display-only, fail-open.

Concurrency: add/remove are atomic-replace writes; the read-modify-write can race under heavy parallel
dispatch (a count may be off by one transiently), and a missed SubagentStop would leak an entry — both are
self-healing via PRUNE (entries older than 30 min are dropped on every read). It's a display, not a ledger.

Importable: agent_activity.py / the status line call render(ws) directly; also usable as a CLI.
"""
import os
import sys
import json
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
try:
    from cdt_emoji import emoji, short
except Exception:                                   # pragma: no cover - fallback if the map is unavailable
    def short(role):
        return (role or "").split(":")[-1].strip() or "agent"

    def emoji(role):
        return "🤖"

PRUNE = 1800   # seconds; entries older than this are assumed dead (a missed SubagentStop) and dropped


def _path(ws):
    return os.path.join(ws, ".claude", "runtime", "running-agents.json")


def load(ws):
    """Current running entries for a workspace, with stale ones pruned."""
    try:
        agents = json.load(open(_path(ws))).get("agents", [])
    except Exception:
        agents = []
    now = time.time()
    return [e for e in agents if isinstance(e, dict) and (now - e.get("ts", 0)) < PRUNE]


def _save(ws, agents):
    p = _path(ws)
    os.makedirs(os.path.dirname(p), exist_ok=True)
    tmp = p + ".%d.tmp" % os.getpid()
    with open(tmp, "w") as f:
        json.dump({"agents": agents}, f)
    os.replace(tmp, p)


def add(ws, role):
    agents = load(ws)
    agents.append({"role": short(role), "ts": time.time()})
    _save(ws, agents)


def remove(ws, role):
    agents = load(ws)
    role = short(role)
    for i, e in enumerate(agents):
        if e.get("role") == role:
            agents.pop(i)
            break
    _save(ws, agents)


def render(ws, max_roles=2):
    """Compact status-line segment, e.g. "🔭 Explore×3 · ⚙️ backend-engineer×1". "" when nothing runs."""
    agents = load(ws)
    if not agents:
        return ""
    counts = {}
    for e in agents:
        r = e.get("role")
        if not r:
            continue
        counts[r] = counts.get(r, 0) + 1
    if not counts:
        return ""
    items = sorted(counts.items(), key=lambda kv: (-kv[1], kv[0]))
    shown = items[:max_roles]
    seg = " · ".join("%s %s×%d" % (emoji(r), r, n) for r, n in shown)
    extra = len(items) - len(shown)
    if extra > 0:
        seg += " +%d" % extra
    return seg


def main():
    cmd = sys.argv[1] if len(sys.argv) > 1 else ""
    if cmd == "add":                                  # payload (with subagent_type + cwd) on CDT_PAYLOAD
        try:
            o = json.loads(os.environ.get("CDT_PAYLOAD", "") or "{}")
        except Exception:
            return
        ti = o.get("tool_input") or {}
        role = ti.get("subagent_type") or ""
        ws = o.get("cwd") or os.getcwd()
        if role:
            add(ws, role)
    elif cmd == "remove":                             # role as arg, workspace on CDT_WS
        ws = os.environ.get("CDT_WS") or os.getcwd()
        role = sys.argv[2] if len(sys.argv) > 2 else ""
        if role:
            remove(ws, role)
    elif cmd == "render":
        ws = os.environ.get("CDT_WS") or os.getcwd()
        print(render(ws))


if __name__ == "__main__":
    try:
        main()
    except Exception:
        pass
