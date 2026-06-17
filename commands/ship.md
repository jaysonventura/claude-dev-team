---
description: Run the completion mandate on the current work and ship (simplify -> review -> reuse-audit -> dead-code -> vault-learning).
allowed-tools: Bash, Read, Grep, Glob, Edit
---

Run the **completion mandate** from the `orchestration` skill on the work in the current session/diff,
scaled to its tier (full mandate if it touched auth/payments/infra/migrations/secrets):

1. **simplify** the changed code (use `/simplify` if available) — reuse over new, remove needless complexity.
2. **code-review** the diff (use `/code-review` if available) — fix blocker/major findings.
3. **reuse-audit** — search for existing utilities the new code duplicates; consolidate.
4. **dead-code scan** — remove anything now unused.
5. **verify** — run the build/tests and paste the output. Do not claim done otherwise.
6. **vault-learning** — append a session note to `~/.claude/vault/sessions/`, a line to `vault/log.md`,
   and any reusable lesson via `cdt-learn "<lesson>"`. Gate-checked: a team-tier session that edited
   files but recorded no lesson is nudged at Stop (`cdt-config memory warn|block|off`).

Report a short SHIP summary. $ARGUMENTS
