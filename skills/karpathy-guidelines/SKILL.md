---
name: karpathy-guidelines
description: Use when writing or reviewing code and you want a simplicity-first engineering bar - minimal, readable, measured. Apply during implementation, refactors, and the simplify step of the completion mandate.
---

# Karpathy-style engineering guidelines

A bias toward **simple, readable, minimal** code that you can reason about.

## Principles
- **Simple beats clever.** Write the boring version that's obviously correct. Cleverness is a cost.
- **Readability is the priority.** Code is read far more than written. Optimize for the next human.
- **Minimize moving parts.** Fewer dependencies, fewer abstractions, fewer layers. Add structure only
  when the pain is real (rule of three before abstracting).
- **Small, composable functions** with one job and honest names. If you can't name it cleanly, it's
  doing too much.
- **Delete code.** The best change is often removal. Less code = less surface for bugs.
- **Make it work, make it right, make it fast — in that order.** Don't optimize before you measure.
- **Measure before optimizing.** Profile; fix the actual hot path, not the imagined one.
- **Strong feedback loops.** Fast tests, quick runs, tight iteration. Verify by running, not by staring.
- **Explicit over implicit.** Obvious data flow; avoid hidden state and spooky action at a distance.

## When reviewing, ask
Is this the simplest thing that works? What can be deleted? Is any abstraction earning its keep? Would a
newcomer understand this in one pass? Is there a measurement behind this "optimization"?
