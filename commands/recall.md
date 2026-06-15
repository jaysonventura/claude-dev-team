---
description: Recall the most relevant durable lessons from the vault for a task or topic (targeted memory retrieval — cheaper than re-reading the whole learnings file).
argument-hint: "<task or query>"
allowed-tools: Bash
---

Retrieve the most relevant past lessons for the user's query by running the recall CLI:

```
~/.claude/bin/cdt-recall "$ARGUMENTS"
```

Present the returned lessons concisely. If nothing relevant comes back, say so plainly — the vault
grows as you complete tasks (the completion mandate appends lessons to `~/.claude/vault/learnings.md`).
