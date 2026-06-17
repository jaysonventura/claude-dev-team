---
name: requirement-intelligence
description: Use when a task references requirement/spec documents (PDF/DOCX/MD), an attached file, "the spec", "requirements", or a doc to implement from. Turns documents into a deterministic, cited requirement set under .claude/specs/ before any code is written.
---

# Requirement intelligence (deterministic spec extraction)

When the work is driven by a document (a PDF/DOCX/Markdown spec, a requirements file, an attached doc), do
NOT skim-and-guess. Extract requirements deterministically and cite their source, then build against the
cited set only.

## How to apply

1. Run the extractor (local, token-free, no external AI by default):
   ```
   cdt-spec <files...>
   ```
   It writes into `<project>/.claude/specs/`: `RAW_TEXT.md`, `DOCUMENT_INDEX.json`,
   `EXTRACTED_REQUIREMENTS.json`, `SPEC_CONTRACT.md`, `TRACEABILITY_MATRIX.md`, `DEV_TASK_BRIEF.md`,
   `QA_TEST_PLAN.md`, `OPEN_QUESTIONS.md`.
2. Read `EXTRACTED_REQUIREMENTS.json` (every requirement carries a **required `source`** reference) and
   `OPEN_QUESTIONS.md`. Resolve open questions and `NEEDS_REVIEW` items with the user before implementing —
   never invent missing requirements.
3. Implement against the cited requirements; map each to a verification in `QA_TEST_PLAN.md` and record
   results via `cdt-verify -- <command>`.

## Guardrails

- **Deterministic by default.** External AI review of documents is OFF unless `CDT_EXTERNAL_AI_ALLOWED=true`
  AND the user approves AND the document is not sensitivity-flagged.
- **Sensitive docs stay local.** Payroll, user data, contracts/legal, secrets, production DB details, and
  auth/payment logic are never sent to an external model; their spec output carries a do-not-commit banner.
- **Images/diagrams** with weak/disabled OCR are marked `NEEDS_REVIEW`, not implemented directly.
- Auto-running on detected docs is off by default (`CDT_SPEC_AUTO=false`); suggest `cdt-spec`, don't force it.
