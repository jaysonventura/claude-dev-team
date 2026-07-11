---
description: Show your current Claude usage (session + weekly %) and the Eco recommendation (conserve when you're running low). Reads the usage cached by the status line / menu bar.
allowed-tools: Bash
---

Report the current budget + Eco recommendation:

```
~/.claude/bin/cdt-budget
```

Explain: **CONSERVE** means the orchestrator will prefer Sonnet, smaller tiers, and skip optional agents
on the next T2+ task (without ever weakening the risk floor or security review). If usage is
"unavailable", suggest enabling the status line: `~/.claude/bin/cdt-config statusline on`.

If the reading is **stale** (or the user works mainly in the VS Code/JetBrains **chat panel**), note that the
status line — the only writer of the % — runs **only in a terminal**. The figure is account-wide, so running
`claude` in the editor's **integrated terminal** (or any terminal) refreshes it everywhere.

A hands-off refresh keeps the panel figure fresh **on by default (popup-free, throttled)**: the menu bar polls
the usage endpoint **read-only, at most ~once every 10 min and only when the terminal reading is stale**, and
merges the result into this same cache. The Keychain read is non-interactive (no macOS prompt on its own); if
access isn't granted it falls back to the cached reading. Disable with
`~/.claude/bin/cdt-config realtime-usage off`.
