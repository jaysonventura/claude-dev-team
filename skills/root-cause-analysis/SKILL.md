---
name: root-cause-analysis
description: Use when debugging any bug, test failure, or unexpected behavior - before proposing a fix. Drives you to the underlying cause instead of patching the symptom. Pairs with superpowers:systematic-debugging.
---

# Root cause analysis

Fix the **cause**, not the symptom. A fix you can't explain is a guess.

## Process
1. **Reproduce reliably.** A bug you can't reproduce, you can't confirm you fixed. Build the minimal repro.
2. **Gather evidence.** The real error, stack, logs, inputs, and the actual code path. Read the code —
   don't theorize from the function name.
3. **Form hypotheses, then falsify.** List plausible causes; test each against evidence with a targeted
   probe. Keep the ones that explain **all** the observations.
4. **Ask "why" until you hit the mechanism** (5 whys). "Null here" → why null → which caller → why that
   path → the real defect.
5. **Confirm before fixing.** Prove the cause (a probe that toggles the behavior). Only then change code.
6. **Fix at the right level**, add a **regression test** that fails before / passes after, and check for
   **siblings** (the same mistake elsewhere).

## Anti-patterns
- Shotgun changes hoping something works. Suppressing the error (try/catch, `?.`, `!`) without
  understanding it. Declaring victory without reproducing the fix. Fixing the symptom one layer above
  the real cause.

## When stuck
Two failed cycles on the same signature → escalate to the **Bug Council** (`/bug-council`) for
multi-lens diagnosis.
