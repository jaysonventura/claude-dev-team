#!/usr/bin/env python3
"""Shared agent-role → emoji map for claude-dev-team's display hooks.

Used by agent_activity.py (the ▶️/✅ transcript lines) and the status line (the live "running agents"
segment), so both render the same icon for a given role. Includes the auto-mode agents (Explore, Plan,
general-purpose, …) that the orchestrator dispatches, not just the named CDT specialists — those previously
fell back to the generic 🤖.
"""

EMOJI = {
    # CDT specialists
    "product-manager": "📋", "architect": "🏛️", "ui-ux-engineer": "🎨",
    "frontend-engineer": "💻", "backend-engineer": "⚙️", "mobile-engineer": "📱",
    "data-engineer": "🗄️", "devops-engineer": "🚀", "qa-engineer": "🧪",
    "security-reviewer": "🔒", "code-reviewer": "🔎", "technical-writer": "📝",
    "diagrams": "📊", "fast-ops": "⚡", "root-cause-analyst": "🔬",
    "adversarial-tester": "💥", "pattern-matcher": "🧩", "systems-thinker": "🕸️",
    "code-archaeologist": "🏺",
    # Auto-mode / built-in agents the orchestrator commonly dispatches
    "Explore": "🔭", "Plan": "📐", "general-purpose": "🤖",
    "claude": "🤖", "claude-code-guide": "📖", "statusline-setup": "🧰",
}


def short(role):
    """Bare role name: drop a "plugin:" namespace prefix (claude-dev-team:qa-engineer → qa-engineer)."""
    return (role or "").split(":")[-1].strip() or "agent"


def emoji(role):
    """Emoji for a role (case-sensitive match on the short name); 🤖 for anything unmapped."""
    return EMOJI.get(short(role), "🤖")
