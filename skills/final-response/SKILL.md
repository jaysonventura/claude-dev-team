---
name: final-response
description: Use before claiming work is complete/fixed/done, or before committing/PR. Enforces the concise 6-field final-response format and an evidence-based verification value. The Stop hook is the source of truth; this skill makes your last message conform.
---

# Final response format (evidence-based)

Before you say a task is done, format your final message exactly like this (keep it under 150 words unless a
detailed report was explicitly requested):

```
Status: <done | partial | blocked | failed | needs_review>
What was done: <one or two lines>
Files changed: <paths>
Verification: <passed | failed | not_run>
Risks: <state any; "none" if none>
Recommended next step: <one step>
```

## Rules (non-negotiable)

- **Never fabricate Verification.** Write `passed` ONLY if a verifying command actually passed. The single
  trusted source is `.claude/runtime/verify-events.jsonl`, and the only way to record a trusted result is:
  ```
  cdt-verify -- <your test/build/lint/typecheck command>
  ```
  If you ran the command directly (not via `cdt-verify`), it counts as `not_run` until you re-run it through
  `cdt-verify`. No observed evidence ⇒ `not_run`.
- **TASK_RESULT.json is local-only** (`.claude/TASK_RESULT.json`). It is for local history/automation; it is
  never sent anywhere and is not a notification.
- The **Stop hook** writes/validates `TASK_RESULT.json` and derives Verification from the evidence — your
  prose must match it, not override it.
- Docs/plan-only sessions legitimately end with `Verification: not_run` (no code to verify).
