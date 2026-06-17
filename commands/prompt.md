---
description: Manually run prompt intake + routing + conditional local enhancement for a task, writing TASK_BRIEF.md, ROUTING.json, and NEXT_PROMPT.md into the project .claude/. (The same engine auto-runs on every non-trivial prompt via the UserPromptSubmit hook.)
---

# /cdt:prompt — prompt intake & routing

Run the deterministic-first prompt engine for the user's task and report the advisory routing.

```
cdt-prompt "$ARGUMENTS"
```

Then:

1. Summarize `ROUTING.json` — tier, model floor, risk domains, whether a security review is required, and the
   recommended agents/gates. Remember routing is **advisory** — you decide the actual dispatch.
2. If `NEXT_PROMPT.md` contains a suggested prompt, treat it as a **suggestion to review**, not an
   auto-submission. Sensitive prompts are never sent to an external model.
3. Proceed with the orchestration workflow using the routing as a prior.

Notes:
- Haiku enhancement (via `claude --bare -p`, your existing login) is used only for genuinely unclear / risky
  / spec-driven prompts and never for sensitive or very short ones.
- `TASK_RESULT.json` (written at Stop) is local-only — nothing is sent anywhere.
