---
name: ui-ux-pro-max
description: Use when pushing a UI from "fine" to "polished and delightful" - micro-interactions, motion, design tokens, and refined states. Advanced layer on top of web-design-guidelines and frontend-design.
---

# UI/UX pro max — the polish layer

Apply after the fundamentals (`web-design-guidelines`) are in place. This is what makes UI feel crafted.

## Design tokens & system
- Drive everything from tokens (color, space, radius, shadow, type, motion) — no hardcoded values.
  Consistency at scale comes from the system, not from eyeballing each component.
- Build real states into components: default / hover / focus / active / disabled / loading / error.

## Motion & micro-interactions
- Motion has **purpose**: feedback, continuity, and directing attention — never decoration for its own
  sake. Keep it fast (≈150–250ms), eased (no linear), and interruptible.
- Animate transforms/opacity (GPU-friendly), not layout. Respect `prefers-reduced-motion`.
- Micro-interactions: button press feedback, input focus, optimistic toggles, skeleton → content,
  subtle success/confirm cues.

## Depth, detail, delight
- Considered elevation/shadow and layering. Pixel-aligned icons, consistent stroke weights.
- Empty states that teach and invite action; error states that explain and offer a way out; loading
  states that feel fast (skeletons over spinners for content).
- Thoughtful defaults and shortcuts; reduce steps; remember user choices.

## Restraint
- Polish is consistency + clarity, not more effects. If an interaction doesn't help the user, cut it.

## Review checklist
Tokenized? Every interactive state designed? Motion purposeful, fast, reduced-motion-safe? Empty/error
states crafted? Does it feel one notch more intentional than "default"?
