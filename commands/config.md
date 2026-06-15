---
description: Enable/disable claude-dev-team and set its defaults (effort, model). Defaults are xhigh effort + Opus 4.8. Writes Claude Code settings safely (applies next session).
argument-hint: "[show | on | off | effort <low|medium|high|xhigh> | model <m> | reset]"
allowed-tools: Bash
---

Run the config CLI with the user's arguments and report the result:

```
~/.claude/bin/cdt-config $ARGUMENTS
```

Notes to convey:
- **on / off** toggles the whole orchestration layer (off → behaves as stock Claude Code next session).
- **effort** / **model** are written to `~/.claude/settings.json` (a safe merge — other settings are
  preserved) and apply on the **next session** (restart Claude Code). Defaults: **xhigh** effort,
  **Opus 4.8** (`claude-opus-4-8`).
- `effort max` is session-only and can't be persisted (use `/effort max`); the recommended persistent
  default is **xhigh**.
- With no arguments, show the current config.
