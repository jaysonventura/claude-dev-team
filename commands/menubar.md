---
description: Build, launch, or manage the claude-dev-team macOS menu bar usage monitor (real subscription % + local token usage).
argument-hint: [install|build|start|stop|status|install-login|uninstall]
allowed-tools: Bash
---

Manage the **claude-dev-team menu bar usage monitor** (a native Swift app showing your real Claude Max
subscription usage — session %, weekly %, Sonnet %, reset countdowns — plus accurate local token usage
from your transcripts and dev-team activity).

Run the control CLI with the requested action (default `install` = build + auto-start + launch):

```
~/.claude/bin/cdt-menubar $ARGUMENTS
```

Notes to relay to the user:
- macOS only; needs the Swift toolchain (`xcode-select --install` if missing). First launch may show a
  one-time macOS Keychain approval prompt — click **Always Allow** so it can read the usage data.
- `install` builds the app, enables auto-start at login (LaunchAgent), and launches it (look for the
  **▓** icon in the menu bar).
- `status` prints a one-shot terminal readout (no GUI). `uninstall` removes the LaunchAgent + binary.
- The subscription %s come from an **undocumented** Anthropic endpoint (may change); the local token
  usage always works regardless.

After running, report the CLI output and remind the user where to look (menu bar icon).
