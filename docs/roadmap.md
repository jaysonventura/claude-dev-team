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
2. **Bounded by default; scale is summoned.** The orchestrator dispatches a *bounded* set of subagents
   per tier (≤6–10) via the normal Agent tool **by default** — it never auto-fans-out. Heavier
   parallelism (dynamic workflows, agent teams) is a **summoned, gated, capped, and measured** mode that
   stays **off** unless you ask for it — so predictable spend never silently becomes runaway spend. (The
   per-agent token telemetry shipped in v1.19.0 is the instrument that keeps scale honest.)
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
| Real per-agent token telemetry (cost safety) | ✅ (v1.19.0) | `SubagentStop` → `agent_runs.tokens` → `/cdt:stats` |
| Gated diagnostic "swarm" for hard bugs | ✅ (bounded) | Bug Council (5 agents) — Phase 5 upgrades it to a debating team |

## Phase 1 — Autonomous Git / CI / PR loop  ·  fit ★★★  ·  effort: medium

**Goal:** extend the Task Loop from *local gates* to the *real VCS*.

- ✅ **Shipped (v1.8.0) — `/cdt:autopilot <PR#> [--live]`:** a `gh`-driven loop (read CI →
  diagnose → focused fix → push → re-check, capped by `CDT_MAX_ITERATIONS`), merge-conflict resolution on
  the branch, and a `code-reviewer` + `security-reviewer` synthesis posted as a PR comment. Backed by a
  read-mostly wrapper (`cdt-pr`) whose only write is a comment. **Safe by design:** dry-run by default,
  **never** force-pushes / auto-merges / closes; merging is the human's call; security review mandatory
  before the "ready" verdict.
- ⏳ **Next:** auto-detect the PR for the current branch; richer failing-log retrieval; optional
  `--merge-when-green` behind an explicit confirmation.

**Fit:** a natural, bounded extension of an existing loop. **Risk** (writes to a real remote) is
contained by the safety rails above. **Cost:** bounded by the iteration cap.

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

- ✅ **Shipped (v1.7.0) — `cdt-advise`:** lexically matches a new task against past `tasks` history and
  returns an **advisory** prior (typical tier, iteration budget, blocker rate). The orchestrator consults
  it on T2+ but still decides — transparent and overridable, never a hidden policy. Pure local DB read,
  no deps. (Adapted from the "ReasoningBank / trajectory learning" idea in `ruflo`, kept on-ethos.)
- ⏳ **Next:** richer signals (which agent roles helped), confidence weighting by sample size, and an
  optional `--explain`.

**Fit:** uses data we already collect. **Risk:** keep nudges transparent and overridable — never a hidden
policy. **Cost:** negligible (reads the local DB).

# Scaling track — parallelism & orchestration at scale

P1–P3 make the team *smarter* (autonomy, memory, routing). The next three make it *wider* — more work in
parallel — built on Claude Code's **official** orchestration primitives (verified against
`code.claude.com/docs`, June 2026). All three are **opt-in and gated**: the bounded, cost-effective core
stays the default; scale is *summoned* for work that genuinely needs it (big parallel features, repo-wide
audits, hard debates). Each is **version-gated** via `cdt-doctor` and **no-ops gracefully** on an older
CLI, and each ships token-budgeted (a dry-run / slice-first before it's ever on by default).

> **Policy note.** Phase 6 (dynamic workflows) is the `ultracode` engine the project's operating rules
> say to avoid *by default*. Adopting it as a **summoned, capped** CDT feature is a deliberate, reviewed
> exception — it does **not** change the everyday default (bounded dispatch, xhigh-never-max). The
> v1.19.0 per-agent token telemetry is the cost-safety instrument that makes the exception affordable.

## Phase 4 — Worktree isolation (parallel builders)  ·  fit ★★★  ·  effort: small

> ✅ **Shipped (v1.20.0).** `cdt-worktree` (`new`/`list`/`path`/`rm`/`clean`) + `/cdt:worktree`, mirroring
> `claude --worktree` (checkout `.claude/worktrees/<name>`, branch `worktree-<name>`). Name-injection
> boundary + dirty-removal protection (security PASS); resolves the main worktree via the git common-dir
> (no nesting from inside a worktree). `cdt-doctor` readiness check; orchestration skill notes it's
> opt-in for large parallel work only. The convention items below are all in.

**Goal:** turn CDT's *disjoint-paths* convention into a *hard* filesystem guarantee.

CDT already forbids two agents writing the same path in a wave. **Git worktrees** enforce it physically —
each parallel builder (or each parallel feature) works in its own checkout + branch, so even shared-file
edits can't collide. Lowest risk of the three, and it needs **no policy change**.

- **Mechanism (official):** `claude --worktree <name>` (alias `-w`) creates `.claude/worktrees/<name>/`
  on branch `worktree-<name>`; the `EnterWorktree` tool lets a session branch mid-flight; a subagent can
  declare `isolation: worktree` in its frontmatter to run in its own temporary worktree (auto-removed if
  it makes no changes). `worktree.baseRef` picks `fresh` (from `origin/HEAD`) vs `head` (carry local
  commits).
- **CDT fit — two synergies that fall out of existing design:**
  - CDT state (the SQLite DB, `.env`, vault, `cdt-*` CLIs) lives in **`~/.claude/`, not the repo**, so
    every worktree inherits the full toolchain with **zero** extra wiring.
  - `/cdt:autopilot` gains true isolation via `claude --worktree "#1234"` (fetches `pull/1234/head` into
    its own checkout).
- **What ships:** add `.claude/worktrees/` to `.gitignore`; an opt-in convention for T3 parallel features
  (each builder isolated); `.worktreeinclude` guidance for any repo-local secrets; a `cdt-doctor` check
  that the CLI supports `--worktree`; cleanup notes (`cleanupPeriodDays`, dirty-tree prompts, and that
  `-p` runs never auto-clean).
- **Risk:** ~nil (file-level isolation + official cleanup). **Cost:** negligible — same agents, isolated
  checkouts.

## Phase 5 — Agent-Team councils  ·  fit ★★☆  ·  effort: medium  ·  gated / experimental

> ✅ **Shipped (v1.21.0)** as the **DEPTH** mode of the autonomous controller (below). `cdt-config teams
> on` sets the experimental flag; STEP 3c convenes the council as a debating team (≤5, time-boxed) on
> `cdt-auto gate team` = ALLOW, else falls back to parallel subagents.

**Goal:** upgrade the Bug Council from *parallel monologues* to a *debate*.

Today the 5 Bug Council agents run as report-only subagents — they can't see or challenge each other, and
the orchestrator synthesizes their separate reports. Claude Code **Agent Teams** give them a shared
**task list + mailbox** so they message and challenge each other directly, which is the entire point of a
council (adversarial-tester pushing back on root-cause-analyst before a verdict).

- **Mechanism (official, experimental):** `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1`; a **lead** session
  spawns 3–5 **teammates** in separate contexts; `teammateMode` = `auto | in-process | tmux` (split
  panes need tmux or iTerm2). Requires **v2.1.32+**.
- **CDT fit:** the council roles already exist as agents — teams just add the communication channel, and
  CDT's synthesis step maps onto the lead reading the mailbox. Wave-2 review (code + security reviewer
  cross-examining) is a second candidate.
- **What ships:** `cdt-config teams on` (**default off**); a `/cdt:bug-council --team` path that spawns a
  real team when enabled and otherwise falls back to today's parallel subagents; docs covering the
  tmux/iTerm2 requirement and the experimental caveats (no `/resume` restore, one team at a time, no
  nested teams, slow shutdown).
- **Risk:** experimental + **linear** token cost (each teammate is a full instance) → gated off, 3–5 cap.
  **Cost:** higher than subagents; reserved for genuinely stuck bugs (the council is already gated to
  those).

## Phase 6 — Dynamic-workflow Scale mode  ·  fit ★★☆  ·  effort: medium  ·  opt-in, capped

> ✅ **Shipped (v1.21.0)** as the **BREADTH** mode of the autonomous controller (below). `cdt-config
> scale on` enables it; STEP 3e summons a workflow only on `cdt-auto gate scale` = ALLOW (auto mode,
> within budget) or a confirmed ASK (assist) — slice-first, contracted, adversarially verified,
> token-capped, with "log what's dropped". Governor **fails safe** to ASK when budget is unknown.

**Goal:** a *governed* realization of the old "bounded swarm" idea — for work bounded dispatch can't cover.

This is the official **Workflows** engine (`ultracode`): a deterministic JS script fans out up to **16
concurrent** subagents (1000 lifetime cap) with intermediate results held in **script variables, not the
orchestrator's context**. CDT uses it **only** where ≤6–10 bounded agents genuinely can't do the job:

- **Repo-wide audits** — e.g. every route checked for a missing auth guard, each finding adversarially
  verified by an independent skeptic.
- **Migrations** — transform every call site in worktree-isolated agents (composes with Phase 4).
- **Exhaustive review** — dimensions × changed files, with find → verify → completeness-critic loops.

- **Mechanism (official):** summoned by an explicit `SCALE:` / `ultracode` prefix or a new **T4** tier —
  *never* auto. `/workflows` to monitor / pause / stop. Requires **v2.1.154+**. (No nested workflows, no
  mid-run user input, session-scoped resume — so multi-stage sign-off runs as separate workflows.)
- **CDT discipline layered on top:** every workflow agent still gets a contract; adversarial-verify +
  completeness-critic stages are mandatory; **run-on-a-slice-first** to gauge spend; **log what's
  dropped** (no silent top-N truncation).
- **The cost-safety instrument:** the **per-agent token telemetry (v1.19.0)** is exactly how Scale mode
  stays affordable — `/cdt:stats` shows which roles burned the budget, and a CDT-level token cap halts
  the run before a 1000-agent *ceiling* becomes a 1000-agent *bill*.
- **Policy:** the deliberate, reviewed exception to "never ultracode" — gated off, summoned, capped; the
  everyday default is untouched.
- **Risk:** the highest of the scaling track (token spend, harder to audit) → gating + caps + telemetry
  are the mitigation. **Cost:** the reason it's opt-in.

## Phase 7 — Federation (research / v2)  ·  fit ★☆☆  ·  effort: large

**Goal:** secure agent-to-agent coordination across machines without leaking data.

- This is effectively a **different product**: transport, mutual auth, a data-redaction boundary, and a
  real threat model. It serves teams/fleets, not a solo Max user. (The headless primitives — `claude -p`,
  `--output-format json`, `--resume`, the Agent SDK — are the building blocks if this is ever pursued.)
- Treated as **research**: a design doc + threat model come *before* any code, and it ships opt-in or not
  at all.

**Fit:** out of scope for the default single-machine product; revisit only if there's a concrete
multi-machine need. **Risk:** the highest — anything networked + agentic needs a careful security review.

## Sequencing

Two tracks, layered:

- **Learning track (on-ethos, shipping):** P1 → P2 → P3 — autonomy + better memory + smarter routing.
- **Scaling track (opt-in):** **P4 (worktrees) first** — safe, cheap, no policy change — then **P5
  (agent-team councils)** and **P6 (Scale mode)** behind explicit opt-in. P4 *composes under* P6
  (worktree-isolated migration agents). **P7 (federation)** stays research-only behind its own
  threat-model doc.

Each phase gets a spec in `docs/specs/`, a **token-budgeted dry-run** before it's on by default, and — if
it touches the macOS menu bar — a notarized DMG with the release. None of P4–P7 changes the bounded,
cost-effective default; they only add capability you can summon.
