---
name: code-splitting
description: Use when a file or module is growing large, when deciding how to break up code, or when optimizing bundle size with lazy/dynamic imports. Applies to both source organization and runtime loading.
---

# Code splitting — organization and loading

## When a file is too big (signal: it's doing too much)
- A file that mixes concerns (UI + data + formatting + types) or scrolls past a few hundred lines is a
  smell. Split by **responsibility**, not by line count.
- Extract: pure helpers → `utils`; types → a `types` module; a sub-feature → its own file/folder.
- Each unit should answer cleanly: *what does it do, how do you use it, what does it depend on?* If you
  can't change its internals without breaking callers, the boundary is wrong.

## Module boundaries
- Depend on **interfaces**, not internals. Keep public surface small; don't export incidental helpers.
- Avoid circular deps (they signal a tangled boundary — extract the shared piece).
- Co-locate things that change together; separate things that change for different reasons.

## Runtime / bundle splitting (web & mobile)
- **Lazy-load** route-level and heavy/rarely-used chunks: dynamic `import()`, `React.lazy` + `Suspense`.
- Split vendor vs app; defer below-the-fold and modal/dialog code.
- Measure with the bundler analyzer before and after — split where it **moves the metric**, not
  reflexively (see `gauge-improvements`). Watch for over-splitting (too many tiny requests).

## Checklist
Is this file one responsibility? Is the public API minimal? Any cycle? Does a lazy boundary actually
reduce initial load (measured)?
