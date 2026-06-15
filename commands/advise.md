---
description: Show an advisory tier/effort prior for a task, learned from how similar past tasks went (reads the local state DB). Advisory only — the orchestrator still decides.
argument-hint: "<task>"
allowed-tools: Bash
---

Run the advisor and present its routing prior for the user's task:

```
~/.claude/bin/cdt-advise "$ARGUMENTS"
```

Summarize the suggested tier, typical iteration budget, and any blocker warning. Make clear this is
**advisory** (derived from past `tasks` history) — not a hard rule. If there's no similar history yet,
say so; it improves as more tasks are logged via the completion mandate.
