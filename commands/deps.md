---
description: Check (and optionally install) claude-dev-team's system prerequisites — python3, git, curl, sqlite3, gh — with the right install command for the user's OS.
argument-hint: "[--install]"
allowed-tools: Bash
---

Run the prerequisite check (or installer):

```
~/.claude/bin/cdt-deps $ARGUMENTS
```

Summarize what's present vs missing. If anything required is missing, offer to run `cdt-deps --install`
(it uses the user's package manager — brew / apt / dnf / winget / …). Make clear: **companion plugins
auto-install** with claude-dev-team, and the scripts use **only python3 stdlib — no pip packages**.
