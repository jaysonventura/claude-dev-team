---
description: Inspect & manage the CDT companion plugins (Superpowers, Code Review, Context7, LSPs, MCPs …). Read-only detection driven by the plugin registry; real install/enable work is shelled out to the `claude plugin` CLI. No destructive uninstall.
argument-hint: "[list [--json] | status | doctor | explain <id> | sync | enable <id> | disable <id> | install <id> | update <id>]"
allowed-tools: Bash
---

Run the plugins CLI with the user's arguments and report the result:

```
~/.claude/bin/cdt-plugins $ARGUMENTS
```

Notes to convey:
- **list / status** shows the health table — `✓` healthy · `!` needs attention (auth/setup) · `○`
  available or disabled · `⨯` missing dependency. `--json` emits a machine-readable `{id: status}` object.
- **doctor** is the same table but exits non-zero only when a **required** plugin or a core dependency is
  broken; non-required issues are warnings.
- **explain `<id>`** describes one plugin — its type, what routes to it (keywords / repo signals), deps,
  auth, security level and fallback behavior.
- **sync** prints the exact `claude plugin install/enable … -s <scope>` commands for any missing enabled
  plugins. It only *runs* them when `CDT_PLUGIN_AUTO_INSTALL=1` **and** `CDT_PLUGIN_STRICT=0`; otherwise it
  is advisory (idempotent — a no-op when everything is present).
- **enable / disable / install / update** are the write verbs. Third-party (non-official) plugins are gated
  by `CDT_PLUGIN_STRICT` (default on) — in strict mode the command is printed, not executed. There is **no
  uninstall**, and needs-auth plugins only get a `/mcp` hint (never auto-authenticated).
- With no arguments, show the plugin health table (`list`).
