---
description: Health-check the claude-dev-team install — hooks, CLIs, state DB, gh, menu bar, companion plugins — and report fixes for anything not green.
allowed-tools: Bash
---

Run the doctor and present the results:

```
~/.claude/bin/cdt-doctor
```

Summarize the `[ok] / [warn] / [FAIL]` lines. For each warning or failure, surface the suggested fix.
End with the one-line tally. If a CLI is missing, note that opening a fresh session re-bootstraps them.
