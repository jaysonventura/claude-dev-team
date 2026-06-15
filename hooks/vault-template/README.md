# claude-dev-team vault

Your project memory. Lives at `~/.claude/vault/` and is Obsidian-compatible (plain markdown + folders —
open this folder as an Obsidian vault if you want the graph view; not required).

- **learnings.md** — durable lessons, gotchas, and patterns. Auto-injected into every session at start.
- **log.md** — one line per shipped task.
- **status-log.md** — every milestone event (delivered / deferred / blocker / ship), mirrored to Discord/Telegram.
- **sessions/** — date-stamped session notes.
- **adrs/** — architecture decision records (one file per significant decision).

The orchestrator appends here during the completion mandate. Keep `learnings.md` tight — it loads every
session.
