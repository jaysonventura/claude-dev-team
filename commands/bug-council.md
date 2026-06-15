---
description: Convene the 5-agent Bug Council to diagnose a stuck or complex bug (root cause + fix plan). Diagnosis only - implementation follows.
argument-hint: <bug symptom / error / failing test>
---

Convene the **Bug Council** (STEP 3c of the `orchestration` skill) for this bug:

Symptom: $ARGUMENTS

1. Gather the real evidence first (error/stack/log, failing test, the relevant files).
2. Dispatch all five diagnostic agents **in parallel, in a single message** (they are read-only):
   `root-cause-analyst`, `code-archaeologist`, `pattern-matcher`, `systems-thinker`, `adversarial-tester`.
3. **Synthesize** their reports into ONE ranked root cause with supporting evidence, plus a concrete
   **fix plan** (and a regression test to add).
4. `~/.claude/bin/cdt-notify INFO "Bug Council verdict: <root cause one-liner>"`.
5. Ask whether to dispatch an engineer to implement the fix (don't auto-fix without confirmation unless
   we're already inside a Task Loop escalation).

Keep the synthesis tight: the ranked cause, the evidence, the plan.
