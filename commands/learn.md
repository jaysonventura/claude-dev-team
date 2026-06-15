---
description: Teach claude-dev-team a durable lesson — appends it to the vault so cdt-recall / cdt-advise surface it on relevant future tasks.
argument-hint: "<lesson>"
allowed-tools: Bash
---

Record the user's lesson in the vault:

```
~/.claude/bin/cdt-learn "$ARGUMENTS"
```

Confirm what was learned. Keep the lesson a single, high-value sentence (the orchestrator also appends
lessons automatically during the completion mandate — this is for teaching it something on demand).
