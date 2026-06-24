---
description: Sync the CDT vault into Obsidian as linked markdown (frontmatter + wikilinks + index), or check sync status / set the vault path.
argument-hint: "[sync|status|set <path>]"
allowed-tools: Bash
---

Run the Obsidian bridge CLI with the supplied argument (defaults to `sync` when none given):

```
~/.claude/bin/cdt-obsidian ${ARGUMENTS:-sync}
```

- **sync** — export `~/.claude/vault` into the configured Obsidian vault now (idempotent; safe to re-run).
- **status** — show the configured vault path and last sync timestamp.
- **set `<path>`** — configure the Obsidian CDT subfolder path (e.g. `~/Documents/Obsidian/CDT`).

To enable auto-sync on session end: `cdt-config obsidian on`
To set the vault path permanently: `cdt-config obsidian-vault <path>`

Present the CLI output to the user. If the vault is not configured, suggest the `set` sub-command and the `cdt-config obsidian on` toggle.
