---
description: Show cost & activity analytics from the local SQLite state DB (sessions, tasks, agents, tiers, blockers, estimated spend).
argument-hint: [today|week|all] (default: week)
allowed-tools: Bash
---

Show the claude-dev-team analytics by running the CLI:

```
~/.claude/bin/cdt-stats $ARGUMENTS
```

Then present the output as a short, readable summary:
- Sessions and tasks in the window, broken down by **tier**.
- **Agent runs** (which roles ran, how often) and average **Task Loop iterations**.
- **Blocker / deferred** rate.
- **Estimated token cost** (clearly labeled an estimate — derived from available Claude Code usage data).

If the DB is empty or the CLI is missing, say so and note it populates as you complete tasks. Add one
line of cost-saving advice if spend skews high (e.g., run more T0/Sonnet sessions, reserve `FULL:`).
