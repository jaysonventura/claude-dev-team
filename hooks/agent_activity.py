#!/usr/bin/env python3
# Shared helper for CDT's "agent activity" CLI display.
# Emits a hook `systemMessage` — shown to the user, NEVER added to the model's context, so it costs ZERO
# tokens. Invoked by two hooks:
#   contract-capture.sh (PreToolUse[Task]) -> CDT_EVENT=dispatch, hook payload on stdin
#   agent-track.sh      (SubagentStop)      -> CDT_EVENT=stop, CDT_AGENT + CDT_TOKENS in env
# Mode (CDT_AGENT_ACTIVITY in ~/.claude/claude-dev-team.env): on (default) | compact | off.
#   on      = dispatch banner (▶️ agent · what) + finish line (✅ agent · N tok)
#   compact = finish line only (less noise, still shows who ran + token cost)
#   off     = nothing
# Fail-open: any error prints nothing and exits 0 (never blocks a dispatch).
import os
import sys
import json

HOME = os.environ.get("CDT_HOME") or os.path.expanduser("~/.claude")

EMOJI = {
    "product-manager": "📋", "architect": "🏛️", "ui-ux-engineer": "🎨",
    "frontend-engineer": "💻", "backend-engineer": "⚙️", "mobile-engineer": "📱",
    "data-engineer": "🗄️", "devops-engineer": "🚀", "qa-engineer": "🧪",
    "security-reviewer": "🔒", "code-reviewer": "🔎", "technical-writer": "📝",
    "diagrams": "📊", "fast-ops": "⚡", "root-cause-analyst": "🔬",
    "adversarial-tester": "💥", "pattern-matcher": "🧩", "systems-thinker": "🕸️",
    "code-archaeologist": "🏺",
}


def mode():
    try:
        with open(os.path.join(HOME, "claude-dev-team.env"), encoding="utf-8") as fh:
            for line in fh:
                if line.startswith("CDT_AGENT_ACTIVITY="):
                    v = line.split("=", 1)[1].strip().lower()
                    return v if v in ("on", "off", "compact") else "on"
    except Exception:
        pass
    return "on"


def short(agent):
    a = (agent or "").split(":")[-1].strip()
    return a or "agent"


def emoji(agent):
    return EMOJI.get(short(agent), "🤖")


def fmt_tokens(n):
    try:
        n = int(n)
    except Exception:
        return "?"
    if n < 1000:
        return str(n)
    if n < 1_000_000:
        return f"{n / 1000:.1f}k".replace(".0k", "k")
    return f"{n / 1_000_000:.1f}M".replace(".0M", "M")


def emit(msg):
    print(json.dumps({"systemMessage": msg}))


def main():
    m = mode()
    if m == "off":
        return
    ev = os.environ.get("CDT_EVENT", "")
    if ev == "dispatch":
        if m == "compact":
            return  # compact shows finish lines only
        try:
            o = json.loads(sys.stdin.read() or "{}")
        except Exception:
            return
        ti = o.get("tool_input") or {}
        agent = ti.get("subagent_type") or ""
        if not agent:
            return
        desc = (ti.get("description") or "").strip()
        line = f"▶️ {emoji(agent)} {short(agent)}"
        if desc:
            line += f" · {desc}"
        emit(line)
    elif ev == "stop":
        agent = os.environ.get("CDT_AGENT", "")
        if not agent:
            return
        emit(f"✅ {emoji(agent)} {short(agent)} · {fmt_tokens(os.environ.get('CDT_TOKENS', '0'))} tok")


try:
    main()
except Exception:
    pass
