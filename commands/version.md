---
description: Show the installed claude-dev-team version (plugin + menu bar app).
allowed-tools: Bash
---

Report the installed claude-dev-team version:

```
~/.claude/bin/cdt-version
```

This prints the **plugin** version (from `.claude-plugin/plugin.json`) and, on macOS, the **menu bar
app** version baked into `CDT Usage.app`. If the two differ, the menu bar binary is stale — rebuild it
with `~/.claude/bin/cdt-menubar build` (or `cdt-menubar install`) so it matches the plugin.

The same version is shown live in the **macOS menu bar dropdown** footer.
