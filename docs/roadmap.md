# Roadmap — toward a learning agent network

**Vision:** evolve `claude-dev-team` from an orchestrated team into a *learning agent network* — one that
plans and dispatches agents, learns from every task, remembers across sessions, drives real Git/CI work
autonomously, and (eventually, opt-in) coordinates across machines without leaking data.

This document is **forward-looking and subject to change**. It exists so the direction is explicit and
reviewable. Nothing here is committed until it has a spec + a shipped version.

## Principles that constrain this roadmap

These are non-negotiable and shape every phase:

1. **Cost-effective on Max 5x.** "Cost" = token / rate-limit budget, not money. Features must not turn
   predictable spend into runaway spend.
2. **Bounded dispatch.** The orchestrator dispatches a *bounded* set of subagents per tier (≤6–10) via
   the normal Agent tool — never a heavy free-form fan-out engine. New capability stays bounded.
3. **Fail-open & local-first.** Hooks/automation must never break a session; default behavior runs on one
   machine with no external services required.
4. **Auditable.** Plain files, grounded claims, verifiable output. No black-box state.
5. **Opt-in for anything heavy or networked.** Swarms and federation are off by default, behind explicit
   flags and a threat model.

## Already shipping — the spine

Much of the "nervous system" vision already exists; the gaps below build *on* it, not from scratch.

| Capability | Status | Where |
|---|---|---|
| Plan tasks, spawn agents, parallel waves | ✅ | `skills/orchestration/SKILL.md` |
| Independent code + security review (with veto) | ✅ | Wave 2 agents |
| Autonomous *local* fix loop (gates → fix → re-run, capped) | 🟡 partial | orchestration §3b Task Loop |
| Remember across sessions | 🟡 partial | `vault/learnings.md` injected at SessionStart |
| Learn from every task | 🟡 partial | mandate vault-learning step + SQLite analytics |
| Gated diagnostic "swarm" for hard bugs | ✅ (bounded) | Bug Council (5 agents) |

## Phase 1 — Autonomous Git / CI / PR loop  ·  fit ★★★  ·  effort: medium

**Goal:** extend the Task Loop from *local gates* to the *real VCS*.

- A `gh`-driven loop: read a PR's CI status → dispatch a focused fix agent on failures → push → re-run →
  repeat (capped by `CDT_MAX_ITERATIONS`).
- A **merge-conflict resolver** agent (read both sides, propose a resolution, gate it).
- **Auto-review** on a PR: run `code-reviewer` + `security-reviewer`, post a structured comment.
- Surfaced as something like `/claude-dev-team:autopilot <PR#>`, reporting via `cdt-notify`.

**Fit:** a natural, bounded extension of an existing loop. **Risk:** writes to a real remote — must be
opt-in, dry-run-able, and never force-push without confirmation. **Cost:** bounded by the iteration cap.

## Phase 2 — Semantic / RAG memory  ·  fit ★★★  ·  effort: medium

**Goal:** turn the vault from "dump 4 KB of markdown every session" into *retrieve what's relevant*.

- ✅ **Shipped (v1.6.0) — lexical recall first cut:** `cdt-recall "<task>"` ranks learnings by term
  overlap (pure stdlib, no deps) and returns only the top matches; SessionStart now injects just the most
  recent lessons + a recall pointer; the orchestration skill recalls on T2+.
- ⏳ **Next:** optional local embeddings for semantic (not just lexical) matching, extend recall over
  `sessions/` + ADRs + the repo, and a persistent task queue so deferred work survives session boundaries.

**Fit:** strictly improves memory quality *and* cost (smaller, sharper context). **Risk:** keep it
local + optional (no cloud embedding service required); fall back to today's markdown if unavailable.
**Cost:** net **saver** — less context per turn.

## Phase 3 — Adaptive routing from history  ·  fit ★★☆  ·  effort: small–medium

**Goal:** close the learning loop — let outcomes tune the process.

- Mine the SQLite history (tier, agent, iterations, blocker rate) for "what usually works for this kind
  of task."
- Nudge triage/model-routing accordingly (e.g. a task class that repeatedly needs a security pass gets
  it earlier).

**Fit:** uses data we already collect. **Risk:** keep nudges transparent and overridable — never a hidden
policy. **Cost:** negligible (reads the local DB).

## Phase 4 — Bounded swarm mode (opt-in)  ·  fit ★☆☆  ·  effort: medium

**Goal:** a *governed* version of "self-organizing swarm" — not the marketing version.

- Opt-in mode where the orchestrator may spawn agents more dynamically **under a hard token budget**,
  stopping when the budget is spent.
- Explicitly **not** free-form emergent behavior — every agent still has a contract and a cap.

**Fit:** tension with the cost-discipline ethos — emergent behavior is expensive and harder to audit.
Only worth it for genuinely huge, parallelizable work, and only behind a flag. **Cost:** the reason it's
gated.

## Phase 5 — Federation (research / v2)  ·  fit ★☆☆  ·  effort: large

**Goal:** secure agent-to-agent coordination across machines without leaking data.

- This is effectively a **different product**: transport, mutual auth, a data-redaction boundary, and a
  real threat model. It serves teams/fleets, not a solo Max user.
- Treated as **research**: a design doc + threat model come *before* any code, and it ships opt-in or not
  at all.

**Fit:** out of scope for the default single-machine product; revisit only if there's a concrete
multi-machine need. **Risk:** the highest — anything networked + agentic needs a careful security review.

## Sequencing

P1 → P2 → P3 are on-ethos, independently shippable, and compound (autonomy + better memory + smarter
routing). P4 and P5 are gated behind explicit opt-in and their own design+threat-model docs. Each phase
gets a spec in `docs/specs/` before implementation.
