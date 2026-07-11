---
description: Build, launch, or manage the claude-dev-team macOS menu bar usage monitor (session/weekly usage % from the CLI status line + local token usage).
argument-hint: [install|build|start|stop|restart|status|install-login|uninstall]
allowed-tools: Bash
---

Manage the **claude-dev-team menu bar usage monitor** (a native Swift app showing your Claude usage —
current-session % and weekly % — plus accurate local token usage from your transcripts and dev-team
activity). The usage %s come primarily from the CLI status line's shared cache (Claude Code's native
`rate_limits`) — a free, local read with no network and no credentials; a popup-free realtime refresh
(on by default) additionally polls the usage endpoint read-only to keep the badge fresh in an editor panel.

Run the control CLI with the requested action (default `install` = build + auto-start + launch):

```
~/.claude/bin/cdt-menubar $ARGUMENTS
```

Notes to relay to the user:
- macOS only; needs the Swift toolchain (`xcode-select --install` if missing). Popup-free — the Keychain
  read for realtime usage is non-interactive, so it never raises a macOS Keychain prompt on its own; a prompt
  appears only if the user clicks **"Grant Keychain access for realtime usage…"** in the dropdown.
- `install` builds the app, enables auto-start at login (LaunchAgent), and launches it (look for the
  **▓** icon in the menu bar).
- `status` prints a one-shot terminal readout (no GUI). `uninstall` removes the LaunchAgent + binary.
- The session/weekly %s come from the CLI status line's cache — enable it with `cdt-config statusline on`
  so the menu bar has data to show; the local token usage always works regardless.
- The status line writes that cache **only from a terminal**, not the VS Code/JetBrains chat panel. If the %
  shows **stale**, tell the user the figure is account-wide and running `claude` in the editor's **integrated
  terminal** (or any terminal) refreshes the menu bar everywhere.
- The hands-off refresh is **on by default (popup-free, throttled)**: the menu bar polls the usage endpoint
  **read-only, at most ~once every 10 min and only when the terminal reading is stale** (≤6 calls/hour, zero
  while a terminal keeps the cache fresh). The Keychain read is non-interactive, so if access isn't granted it
  quietly falls back to the cached reading (a calm *"Realtime paused — grant Keychain access"* line). Disable
  with `cdt-config realtime-usage off`; force one gated refresh now with `cdt-menubar --refresh-usage`.

After running, report the CLI output and remind the user where to look (menu bar icon).
