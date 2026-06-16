# Spec — claude-dev-team Enforcement Gates (code-backed discipline layer)

Date: 2026-06-16 · Status: shipped (v1.24.0–v1.28.0)

## Context & goal

CDT's vision is a discipline layer that fixes the predictable LLM-coding failures *structurally* —
"contracts force grounding, gates force verification". Audit found the vision was ~90% **documented and
trusted to the model**, not enforced by code; only cost-governance, per-agent telemetry, and
least-privilege tools were genuinely code-backed. This track turns the four headline promises into
**hooks + CI** so the discipline holds even when the model would skip it — while honoring CDT's fail-open,
stay-cheap philosophy.

## Design principles

- **Detect / surface / block, not author.** A Claude Code plugin can't pre-empt a single subagent write;
  it can observe (PostToolUse / SubagentStop) and block at `Stop`. Gates verify the work; the orchestrator
  still does the work (writes contracts, picks tiers, runs review). That boundary is stated, not hidden.
- **Default-on but configurable.** Each gate ships enabled (verify=block, scope/memory=warn) and softens
  via `cdt-config` / `CDT_*` env (single-key `grep` read — never `source` the env file).
- **Fail-open, once per session.** No `python3` / no marker / any error → never blocks. A per-session
  marker means a gate fires at most once, so the user is never trapped.
- **Grounded telemetry.** Every gate outcome is recorded to the state DB (`events.type`) for `/cdt:stats`.

## The gates

| # | Gate | Hook(s) | Mechanism | Config |
|---|---|---|---|---|
| 1 | **Verify** (false "done") | PostToolUse `Bash` + `Stop` + SubagentStop | `verify-track.sh` marks the session "verified" on a verb-anchored test/build/lint command (`verify-lib.sh` allowlist); `agent-track.sh` also marks it when a *subagent* ran one; `completion-guard.sh` blocks if the edit-marker is newer than the verify-marker (tie → verified), with a main-transcript rescue scan. | `cdt-config verify block\|warn\|off` |
| 2 | **Grounding** (hallucinated APIs) | CI | Builder agents carry only the two `context7` doc tools; `lint-agents.sh` relaxes the mcp ban to exactly those and **requires** the six engineering builders to keep them. | always on |
| 3 | **Scope** (10-file sprawl) | PreToolUse `Task` + SubagentStop + `Stop` | `contract-capture.sh` records each dispatch's `CDT-CONTRACT: exclusive=…` to `~/.claude/.cdt/contracts/<sid>/`; `agent-track.sh` atomically claims it (lock-free `mv`, concurrency-safe) and diffs the agent's transcript writes vs the contract (`scope-lib.sh`, lenient globs) → overreach / collision. | `cdt-config scope warn\|block\|off` |
| 4 | **Memory** (forgets lessons) | `Stop` | `completion-guard.sh` nudges a *team-tier* session (≥1 `agent_runs` row; solo exempt) that edited but recorded no fresh `learnings.md`. `recall.sh` re-ranks relevant lessons by recency (exp decay) + outcome (terms from high-iteration/blocked tasks). | `cdt-config memory warn\|block\|off` |
| 5 | **Cost truthfulness** | `Stop` + `cdt-auto` | `usage-lib.sh` shared token-sum; `completion-guard.sh` records orchestrator-vs-delegated overhead; `cdt-auto slice record`/`project` + a `gate scale` check make **slice-first** a code gate before any BREADTH fan-out. | `cdt-auto`, `cdt-config eco` |

## Hook map (`hooks/hooks.json`)

- `PreToolUse: Task` → `contract-capture.sh` (gate 3 capture)
- `PostToolUse: Edit|Write|MultiEdit` → `format-on-write.sh` (edit marker) · `PostToolUse: Bash` → `verify-track.sh` (gate 1)
- `SubagentStop` → `agent-track.sh` (telemetry + gates 1, 3, 5)
- `Stop` → `completion-guard.sh` (gates 1, 4, 5 + scope surfacing)

## Verification

`bash scripts/validate.sh && bash scripts/lint-agents.sh && bash scripts/e2e.sh` (sandboxed; ~50
assertions across the gates incl. matcher precision, a scope concurrency double-claim, recency ordering,
and slice projection). Negative tests confirm CI fails when a builder loses context7.

## Known limits / trade-offs

- Gate 1 assumes the edit and verify markers share a scope (the PostToolUse channel); the subagent-marker
  path makes it robust even if PostToolUse doesn't fire for subagents.
- Gate 3 attribution is transcript-derived (not `git diff`) because parallel agents share one tree; glob
  matching is deliberately lenient (favours not-flagging) and defaults to `warn`.
- The contract *write* side (the orchestrator emitting `CDT-CONTRACT:`) remains agreement-based; the
  read/diff/flag side is fully code-enforced.
