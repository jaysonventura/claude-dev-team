---
description: Deterministically extract requirements from spec documents (PDF/DOCX/MD/images) into .claude/specs/ with cited sources. Local + token-free by default; sensitive docs stay local; weak diagrams are marked NEEDS_REVIEW.
---

# /cdt:spec — requirement/spec extraction

Extract a cited requirement set from the given document(s):

```
cdt-spec $ARGUMENTS
```

Then:

1. Read `.claude/specs/EXTRACTED_REQUIREMENTS.json` (every requirement carries a required `source`) and
   `.claude/specs/OPEN_QUESTIONS.md`.
2. Resolve open questions and any `NEEDS_REVIEW` items **with the user** before implementing — do not invent
   missing requirements.
3. Implement against the cited requirements; record verification via `cdt-verify -- <command>`.

Guardrails: deterministic by default; external-AI document review requires `CDT_EXTERNAL_AI_ALLOWED=true` +
approval + a non-sensitive document; sensitivity-flagged outputs carry a do-not-commit banner and are never
sent externally.
