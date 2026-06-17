---
description: Autonomously drive a GitHub PR toward green — read CI, diagnose + fix failures, resolve conflicts, re-run gates, and post a review. Safe by default (dry-run); never force-pushes or auto-merges.
argument-hint: "<PR#> [--live]"
allowed-tools: Bash, Read, Edit, Write, Grep, Glob, Task
---

Run the **PR AUTOPILOT** loop (orchestration skill, STEP 3d) on: `$ARGUMENTS`

Safety is non-negotiable:
- **Dry-run by default.** Without `--live`, only read + report: the PR's CI status, your diagnosis of any
  failures, and the *exact* plan (what you would change). Make **no** commits, pushes, or comments.
- With `--live` you may act — but **never force-push, never auto-merge, never close the PR.** Pushes go
  to the PR branch with a normal `git push`; merging is the user's explicit decision.
- Bound the fix loop by `CDT_MAX_ITERATIONS`; stop and report to the user if you hit the cap.

Use `~/.claude/bin/cdt-pr {status|checks|view|diff|comment} <PR>` for PR data. Confirm `gh` is
authenticated first. Follow the skill's STEP 3d exactly.
