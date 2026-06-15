---
description: Preview the triage tier and proposed agent dispatch for a task WITHOUT executing it, so you can confirm or override.
argument-hint: <task description>
---

Run **STEP 1 · TRIAGE** from the `orchestration` skill on this task, but **do not execute** — only
preview so I can confirm or override:

Task: $ARGUMENTS

Output:
1. **Score** — files / domains / keyword / risk (and whether the risk floor forces T2+).
2. **Tier** — T0 / T1 / T2 / T3, with one line of justification.
3. **Proposed dispatch** — which agents, in which waves, and each one's exclusive file scope.
4. **Estimated cost posture** — which calls would be Opus (judgment) vs Sonnet (throughput), and
   whether the full or light completion mandate would run.
5. **Overrides** — remind me I can reply `T0:` (force solo/cheap) or `FULL:` (full-Opus + all gates).

Stop after the preview. Wait for my go-ahead.
