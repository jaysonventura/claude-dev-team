---
name: gauge-improvements
description: Use before claiming a change is an improvement - performance, refactor, or optimization. Defines "better" measurably so you don't ship premature optimization or unverified wins.
---

# Gauge improvements — prove it's actually better

Never assert "this is faster / cleaner / better" without evidence.

## Define "better" first
- Pick the **metric** that matters: latency (p50/p95/p99), throughput, memory, bundle size, build time,
  query time, or a readability/complexity proxy (LOC, cyclomatic complexity, file count).
- State the **target and the constraint** (e.g., "p95 < 200ms without raising memory").

## Measure honestly
- **Baseline before, same conditions after.** Control inputs, warm-up, and environment. Run enough
  iterations to beat noise; report variance, not a single lucky run.
- Use real tools: a profiler/benchmark, the bundler analyzer, `EXPLAIN ANALYZE`, timing harnesses — not
  vibes. Profile to find the **actual** hot path before optimizing it.

## Decide
- Keep the change only if the metric moved **meaningfully** beyond noise **and** nothing important
  regressed (correctness, other metrics, readability).
- Beware micro-optimizations with no measured impact — they add complexity for nothing (YAGNI).
- For refactors, "better" = simpler/clearer with tests still green; say what got simpler and why.

## Report
`metric · before · after · delta · conditions/iterations`. If it didn't move, say so and revert.
