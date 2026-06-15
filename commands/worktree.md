---
description: Manage git-worktree isolation for parallel CDT work — create/list/remove isolated checkouts under .claude/worktrees/<name> (interops with `claude --worktree`). Safe by default; removal refuses dirty worktrees without --force.
allowed-tools: Bash
---

Run the `cdt-worktree` helper with the user's arguments (default to `list` if none):

```
~/.claude/bin/cdt-worktree $ARGUMENTS
```

Subcommands: `new <name> [base]` · `list` · `path <name>` · `rm <name> [--force]` · `clean` · `help`.

Use this to isolate parallel work — each builder or feature gets its own checkout + branch, so even
shared-file edits can't collide. It mirrors Claude Code's native convention: `cdt-worktree new feat`
and `claude --worktree feat` open the **same** checkout (`.claude/worktrees/feat`, branch
`worktree-feat`).

Present the output plainly. If a removal is refused, surface the safe options (commit/stash, or
`--force`). After finishing work in a worktree, remind the user to commit + merge back via their normal
git/PR flow, then `cdt-worktree rm <name>` to clean up.
