---
name: web-design-guidelines
description: Use when building or reviewing web UI for visual quality and usability - spacing, hierarchy, typography, color/contrast, responsiveness, accessibility, and performance. Pairs with frontend-design.
---

# Web design guidelines

Foundations that separate polished UI from generic output.

## Layout & spacing
- Use a consistent **spacing scale** (4/8px rhythm); align to a grid. Whitespace is a feature — don't crowd.
- Establish clear **visual hierarchy**: size, weight, color, and spacing guide the eye to what matters
  first. One primary action per view.

## Typography
- Limited type scale (a handful of sizes), generous line-height (~1.5 body), measure ~60–75 chars.
  Strong heading/body contrast. 1–2 families max.

## Color & contrast
- A small, intentional palette (neutrals + 1 accent). Meet **WCAG AA** contrast (4.5:1 text, 3:1 large).
  Don't rely on color alone to convey meaning. Support dark mode via tokens, not hardcoded hex.

## Responsive
- Mobile-first; fluid layouts; test real breakpoints. Tap targets >= 44px. Respect safe areas and
  `prefers-reduced-motion`.

## Accessibility (non-negotiable)
- Semantic HTML; labels for inputs; visible focus states; keyboard-operable; alt text; ARIA only when
  semantics fall short. Announce async state changes.

## States & feedback
- Design **loading, empty, error, and success** states — not just the happy path. Optimistic UI where safe.

## Performance (UX is speed)
- Minimize layout shift (CLS), lazy-load below the fold, optimize/responsive images, avoid blocking the
  main thread. Measure (see `gauge-improvements`).

## Review checklist
Hierarchy clear? Spacing consistent? AA contrast? Keyboard + focus? All four states? Responsive at real
breakpoints? No CLS jank?
