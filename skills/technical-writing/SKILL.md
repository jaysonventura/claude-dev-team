---
name: technical-writing
description: Use when writing or editing user-facing documentation - README, guides/tutorials, API docs, release notes, CHANGELOG, ADRs, or PR descriptions. Conventions for docs that are accurate, scannable, and stay current. Pairs with the technical-writer agent.
---

# Technical writing — clear, accurate, current

Good docs let a stranger succeed on the first try. Optimize for the reader's time, not the writer's.

## Accuracy first (non-negotiable)
- **Ground every claim** in real code/output. Run the commands; paste the actual result. Never invent
  APIs, flags, file paths, counts, or version numbers.
- **Docs ↔ reality must match.** If the doc says "10 agents" or `/foo:bar`, verify it exists. A wrong
  command or stale count destroys trust faster than a missing one.
- Document **what exists**, not what's planned (put roadmap items under a clearly-labelled roadmap).

## Structure for scanning
- **Lead with the answer / the why**, then the how-to. Readers skim — front-load value.
- Use **headings, short paragraphs, tables, and lists**. One idea per paragraph.
- Every example should be **copy-paste runnable**. Show expected output where it helps.
- Keep a **table of contents** for long docs; cross-link instead of duplicating.

## Voice & consistency
- Match the project's existing **tone and terminology** — don't introduce a synonym for an established term.
- Be **plain and direct**; cut marketing fluff and hedging. Active voice, present tense.
- Define a term once at first use; assume the reader is smart but new to *this* project.

## Release notes / CHANGELOG / PR descriptions
- State **what changed and why** in one line a user understands; group by Added / Changed / Fixed.
- Call out **breaking changes** and the **migration step** explicitly.
- Link the relevant code/PR; keep entries newest-first and versioned.

## Keep it current
- When code/behavior changes, update the affected sections **in the same change** — counts, version
  badges, command names, screenshots. Stale docs are worse than none.
