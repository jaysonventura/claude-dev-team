---
description: Inspect & control CDT's Autonomous Agent Orchestration — the mode router (BOUNDED / DEPTH agent-team / BREADTH workflow) and its cost governor. status · gate <team|scale> · explain "<task>" · off|assist|auto.
allowed-tools: Bash
---

Run the autonomous-orchestration controller with the user's arguments (default `status`):

```
~/.claude/bin/cdt-auto $ARGUMENTS
```

- **`status`** — show the autonomy mode (off/assist/auto), the DEPTH (teams) + BREADTH (scale) engines, the caps, and live weekly-budget headroom.
- **`gate <team|scale>`** — the governor decision the orchestrator consults before escalating: `ALLOW` / `ASK` / `DENY`.
- **`explain "<task>"`** — advisory preview of which mode the live router would lean to for a task.
- **`off | assist | auto`** — set the autonomy leash (delegates to `cdt-config autonomy`).

Present the output plainly. If the user is enabling escalation, remind them: **agent teams** need `cdt-config teams on` (sets the experimental flag), **scale mode** needs `cdt-config scale on` + Claude Code ≥ 2.1.154, and the default **assist** mode auto-runs teams on stuck bugs but asks before a workflow. The default path stays **BOUNDED** — escalation fires only on signature and within budget.
