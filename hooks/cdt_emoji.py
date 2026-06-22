#!/usr/bin/env python3
"""Shared role-name helper for claude-dev-team's display hooks.

Used by agent_activity.py (the dispatch/finish lines) and running_agents.py (the live running-agents
tracker) so both normalize an agent role the same way. CDT's terminal/CLI output is plain text — the old
role→emoji icon map was removed.
"""


def short(role):
    """Bare role name: drop a "plugin:" namespace prefix (claude-dev-team:qa-engineer → qa-engineer)."""
    return (role or "").split(":")[-1].strip() or "agent"
