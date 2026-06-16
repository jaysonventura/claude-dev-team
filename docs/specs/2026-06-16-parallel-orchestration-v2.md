# Spec — claude-dev-team Parallel Orchestration v2

Date: 2026-06-16 · Status: shipped (P1 v1.29.0 · P2 v1.30.0 · P3 v1.31.0 · P4 v1.32.0 · P5 v1.33.0)

## Context & goal

CDT already does multi-agent parallel execution (Wave 0→1→2 dispatched as parallel `Agent` calls,
per-agent model pins, BOUNDED/DEPTH/BREADTH modes, a weekly-budget cost governor, per-agent +
orchestrator-overhead telemetry, and the enforcement gates). This track pushes that engine to hit **four
goals at once**:

1. **Production-grade** — output good enough to ship.
2. **High quality** — correct, reviewed, no sloppy work.
3. **Fast shipping** — short wall-clock from request to a verified, shipped result.
4. **Cost-effective tokens** — minimal spend for that result.

**Governing rule (non-negotiable, applies to every phase):** *production-grade model floor.* Judgment /
review / security / architecture run on **Opus**; substantive build/test run on **Sonnet** (Opus on
risk); **Haiku is used only for trivial, zero-judgment mechanical ops** (`fast-ops`). Cost-effectiveness
is achieved *above* this floor — by budgets, dedup/caching, right-sizing Sonnet↔Opus, and parallel
wall-clock — **never** by routing real work to a model that can't do it.

## Baseline — preserved in full (this track ADDS to it; it removes nothing)

The existing CDT runtime stands exactly as-is. v2 only *enhances* named points in the flow; every box
below stays:

- **Request flow (unchanged):** USER REQUEST → **STEP 1 Triage** (tech-lead, <5s — `score = files +
  domains + keyword + risk`; risk override auth/payments/infra/migrations/secrets → T2+; vault read
  README + learnings on T2+; **T0 solo · T1 pair 0–1 · T2 squad 3–5 · T3 full 6–10 agents**) → **STEP 2
  Contract** per agent (types & signatures · **EXCLUSIVE file ownership, no overlaps** · files-you-may-read
  · DONE WHEN (verifiable) · DO NOT · REPORT ≤150 words + fenced evidence) → **STEP 3 Execute**
  (single-message parallel: Wave 0 research/specs · Wave 1 build exclusive-scope · quality-gate chain ·
  Wave 2 independent review) → **STEP 4 Completion mandate** (**every tier, no carve-outs** — 1 simplify ·
  2 code-review · 3 reuse-audit · 4 dead-code-scan · 5 vault-learning; runs even on a T0 single-file fix)
  → **SHIP** → **Persistence** (vault: sessions · ADRs · learnings · log).
- **Agent layer (unchanged):** the specialist roster — tech-lead orchestrator + backend · frontend ·
  ui-ux/design · QA · security · PM/product · devops · technical-writer · diagrams · mobile · architect ·
  the gated 5-agent Bug Council — each under **exclusive file scope per dispatch**. **Security veto stays**
  (blocks ship on risk ≥ medium).
- **Quality-gate chain (unchanged):** fmt · lint · typecheck · unit · integration · build · smoke ·
  wave-2 review · vault-close; FAIL → the Task-Loop fix-agent.
- **Skill layer (unchanged, ~50 skills):** orchestration · quality (simplify, code-review,
  clean-code-typescript, karpathy-guidelines, code-splitting, gauge-improvements, security-review,
  verification-before-completion) · debugging (systematic-debugging, test-fixing, root-cause-analysis) ·
  development (TDD, git-worktrees, finishing-a-branch, receiving-code-review, fix-build) · discovery
  (brainstorming, prd, research) · design (frontend-design, ui-ux-pro-max, web-design-guidelines, figma) ·
  media.
- **Enforcement gates (unchanged — v1.24.0–v1.28.0):** verify · grounding · scope · memory · cost.

**Where v2 plugs in (additive map):** P1 → Wave 1 dispatch (worktrees) + triage→fan-out sizing · P2 →
Wave 0 (the research/vault step now emits a shared context pack into STEP 2 contracts) · P3 → STEP 1/2
(per-dispatch model choice, under the floor) · P4 → Wave 2 + the quality-gate chain (adversarial /
diverse-lens) and Wave 0 (design judge-panel) · P5 → STEP 1 (advise prior) + STEP 4 / SHIP / Persistence.
Nothing in the baseline is moved or removed.

## Design principles

- **Improve bounded dispatch; do NOT build a scheduler engine.** Per the operator's standing rule, this
  track never invokes the ultracode / Workflow fan-out engine and never builds a deterministic DAG
  scheduler. Quality patterns (judge panel, adversarial verify) are done with a *handful of ordinary
  parallel `Agent` calls*, budget-gated — not a Workflow.
- **Code where it can be, prompt where it must be** (same as the enforcement track). New advisory CLIs +
  governor extensions + lint make routing/cost measurable and gated; SKILL.md teaches the orchestrator
  the parallel patterns; telemetry + lint keep it honest.
- **Fail-open, cheap by default.** New CLIs degrade to no-op without `python3`; advisories never block;
  small/low-risk tasks stay on the cheap fast path (no new ceremony).
- **Additive only — the baseline stays whole.** Every box in "Baseline — preserved in full" remains: the
  4-step flow, the agent roster + security veto, the quality-gate chain, the ~50 skills, the completion
  mandate (every tier, no carve-outs), and the v1.24.0–v1.28.0 enforcement gates. v2 enhances named points
  in the flow; it never moves or removes a baseline element. Eco/elastic trimming drops only *optional*
  agents, never the security review or the verify gate.
- **Each phase = one shippable CDT version** with CLI/hooks + `e2e.sh` coverage + a `plugin.json` bump.

## Non-goals

- A Workflow/ultracode fan-out engine or a deterministic DAG scheduler.
- Routing substantive work to Haiku to save tokens (violates the floor).
- Removing or softening any enforcement gate from v1.24.0–v1.28.0.
- `max` effort (stays `xhigh`).

---

## P1 · Fast parallel dispatch  *(goals: fast shipping, cost)*

**Mechanism.** Maximize true concurrency and size it to the budget.
- **Worktrees-by-default for parallel multi-writer waves (T2+ with ≥2 concurrent builders, all of T3).**
  Each parallel strand gets its own `cdt-worktree` checkout so writes never collide and agents genuinely
  run in parallel. The scope gate (v1.26.0) *detects* collisions; worktrees *prevent* them and unlock
  wall-clock. Single-writer or small waves stay in-place (worktree setup isn't free).
- **Elastic fan-out** — `cdt-auto fanout <tier>` recommends the parallel-agent count from remaining
  weekly headroom (reuses `weekly_pct` + `CEILING`): full tier width when there's room, trimmed to
  essentials when tight — but **never below the floor** (security-reviewer + qa verify always survive).
- **Low-risk fast path** — SKILL.md: for T0/T1 low-risk changes, skip optional Wave-0/Wave-2 agents and
  go solo/pair → ship fast. Formalizes "small stays cheap and quick."

**Files.** `hooks/auto.sh` (`fanout` subcommand) · `hooks/worktree.sh` (unchanged; used by default) ·
`skills/orchestration/SKILL.md` STEP 3 (worktree-default rule + fast path) · `claude-dev-team.env.example`
(`CDT_WORKTREE_DEFAULT`, `CDT_FANOUT_*` if needed) · `README.md` · `CHANGELOG.md` · version bump.
**Tests.** `e2e.sh`: `cdt-auto fanout` returns a smaller count at high weekly %, full count at low %; the
floor agents are always included.

## P2 · Shared-context packs (dedup)  *(goals: cost, fast shipping)*

**Mechanism.** Parallel agents currently each re-read the same files — the biggest avoidable parallel
cost and a ramp-time drag. Instead:
- A **Wave-0 context pack**: an `Explore`/`architect` pass (or `cdt-context pack <paths…>`) distills the
  shared context **once** into a compact manifest — relevant file list + key signatures/exports +
  conventions — written to `~/.claude/.cdt/context/<session>.md`.
- The orchestrator **injects the manifest** into each builder's contract (as the READ summary) so agents
  consume the distilled context instead of re-discovering it.
- **Cache-friendly dispatch ordering** — structure prompts so the shared manifest is the stable prefix,
  maximizing Anthropic prompt-cache hits across the parallel agents.

**Files.** `hooks/context.sh` (`cdt-context pack` — file list + `grep`/signature extraction to a manifest;
pure stdlib, fail-open) · `skills/orchestration/SKILL.md` STEP 2/3 (build + inject the pack; cache
ordering) · `session-start-vault.sh` (install `cdt-context`; GC old packs) · `README.md` · `CHANGELOG.md`.
**Tests.** `e2e.sh`: `cdt-context pack` over a temp tree emits a manifest containing the files + extracted
signatures; absent python3 degrades gracefully.

## P3 · Production-grade model right-sizing  *(goals: production-grade, cost)*

**Mechanism.** Spend Opus where it pays, Sonnet where it's enough, **never below the floor**.
- **`cdt-route "<subtask>"`** — advisory recommendation of **Opus | Sonnet** (and `fast-ops`/Haiku only
  for explicitly trivial mechanical work) from difficulty signals, reusing the keyword-classifier pattern
  in `cdt-auto explain`: risk (auth/payments/infra/migration/secrets) → Opus; ambiguity/novelty/design/
  architecture/review → Opus; mechanical throughput (scaffolding, well-specified build/test) → Sonnet;
  trivial rename/format/list → Haiku via `fast-ops`. **It never recommends Haiku for substantive work.**
- **Floor lint** — extend `scripts/lint-agents.sh`: judgment roles stay `model: opus` (already checked);
  add an assertion that **no substantive agent is pinned to Haiku** (only `fast-ops` may be Haiku), and
  document the Sonnet-minimum floor for builders. SKILL.md tells the orchestrator to consult `cdt-route`
  per dispatch and records the chosen model.

**Files.** `hooks/route.sh` (`cdt-route`) · `scripts/lint-agents.sh` (floor checks) ·
`skills/orchestration/SKILL.md` (routing step + floor rule) · `session-start-vault.sh` (install
`cdt-route`) · `README.md` · `CHANGELOG.md`.
**Tests.** `e2e.sh`: `cdt-route "add auth refresh"` → Opus; `cdt-route "scaffold a CRUD endpoint"` →
Sonnet; `cdt-route "rename a variable across files"` → fast-ops/Haiku; lint fails if a builder is Haiku.

## P4 · Quality-via-parallelism (bounded)  *(goal: high quality)*

**Mechanism.** Bring Workflow-style quality into *bounded* dispatch — a few parallel `Agent` calls on
production models, **budget-gated** (don't always pay for N attempts):
- **Adversarial verify** — for a risky change/finding, dispatch 2–3 *independent* reviewers (Opus)
  prompted to **refute** (default to "not proven" when uncertain); if a majority refute, rework before
  ship. A focused Wave-2.5 reserved for risk-flagged work.
- **Diverse-lens review** — Wave-2 reviewers each take a *distinct* lens (correctness · security · perf ·
  a11y/UX) rather than overlapping, so redundancy doesn't hide a failure mode.
- **Design judge-panel (optional, Wave-0)** — for genuinely ambiguous design, 2–3 independent `architect`
  variants → a judge scores → synthesize from the winner. Gated on high ambiguity **and** budget headroom.

These are SKILL.md orchestration patterns, gated by **tier + risk + `cdt-auto` budget** so they engage
only when warranted. No new engine; just disciplined bounded fan-out.

**Files.** `skills/orchestration/SKILL.md` (the three patterns + when each fires; reuse existing
`code-reviewer`/`security-reviewer`/`architect`) · `commands/` (optional `/cdt:adversarial`) · `README.md`
· `CHANGELOG.md`.
**Tests.** `e2e.sh` is light here (these are prompt patterns); add a `lint`/doc check that the patterns +
their budget/tier gates are documented, and that they reuse production-model agents (no Haiku).

## P5 · Adaptive feedback + ship integration  *(goals: all four)*

**Mechanism.** Close the loop and make shipping itself fast.
- **`cdt-advise` learns the cost/speed-effective mix** — extend the prior to mine `tasks` + `agent_runs`
  (+ the dispatch budgets) for *which model/agent-count mix shipped green fastest/cheapest* for similar
  work, and recommend it ("similar tasks shipped green on Sonnet ×2 in 1 iteration — start there").
- **Ship integration** — after the gate chain passes, the fast path flows straight into `cdt:ship` /
  `cdt:autopilot` so a green, verified change ships without manual ceremony.
- **Honesty pass** — README/docs reconcile the new advisories vs what stays model-driven; update the
  enforcement/orchestration docs.

**Files.** `hooks/advise.sh` (mix recommendation) · `skills/orchestration/SKILL.md` STEP 4 + `commands/
ship.md` · `README.md` · `docs/` · `CHANGELOG.md`.
**Tests.** `e2e.sh`: with seeded `tasks`/`agent_runs`, `cdt-advise` returns a model/agent-count mix
recommendation.

---

## Verification (whole track)

Per phase: `bash scripts/validate.sh && bash scripts/lint-agents.sh && bash scripts/e2e.sh` green (e2e in
a sandbox `$HOME`), plus the demo unittests. New advisory CLIs (`cdt-auto fanout`, `cdt-context`,
`cdt-route`) get direct e2e assertions; the floor lint gets a negative test (a Haiku builder fails CI).
End-to-end smoke on a scratch repo: a T2 feature should dispatch in parallel (worktrees), consume a
shared context pack, route models above the floor, pass the gates, and ship — measurably fewer tokens and
shorter wall-clock than the same task pre-track (compare via `/cdt:stats` overhead + agent tokens).

## Sequencing & YAGNI

P1–P3 are the cost+speed+floor core and compound (do these first). P4 is the quality core. P5 is
adaptive polish and may fold into P1/P3 if a leaner track is preferred. If cutting to three phases:
**P1 + P2 + P3**.
