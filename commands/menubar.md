---
description: Build, launch, or manage the claude-dev-team macOS menu bar usage monitor (session/weekly usage % from the CLI status line + local token usage).
argument-hint: [install|build|start|stop|restart|status|install-login|uninstall]
allowed-tools: Bash
---

Manage the **claude-dev-team menu bar usage monitor** (a native Swift app showing your Claude usage —
current-session % and weekly % — plus accurate local token usage from your transcripts and dev-team
activity). The usage %s are read from the CLI status line's shared cache (Claude Code's native
`rate_limits`); the menu bar makes no network calls and reads no credentials.

Run the control CLI with the requested action (default `install` = build + auto-start + launch):

```
~/.claude/bin/cdt-menubar $ARGUMENTS
```

Notes to relay to the user:
- macOS only; needs the Swift toolchain (`xcode-select --install` if missing). No Keychain prompt — the
  menu bar reads no credentials.
- `install` builds the app, enables auto-start at login (LaunchAgent), and launches it (look for the
  **▓** icon in the menu bar).
- `status` prints a one-shot terminal readout (no GUI). `uninstall` removes the LaunchAgent + binary.
- The session/weekly %s come from the CLI status line's cache — enable it with `cdt-config statusline on`
  so the menu bar has data to show; the local token usage always works regardless.

After running, report the CLI output and remind the user where to look (menu bar icon).
