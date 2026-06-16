# Changelog

All notable changes to claude-dev-team. Versions follow semver.

## [1.34.1] — 2026-06-16
### Docs
- README: new **"Updating CDT (get the latest version)"** section — `claude plugin marketplace update
  claude-dev-team` + `claude plugin update cdt@claude-dev-team` (restart to apply), `/cdt:version` to
  check, and how to refresh the macOS menu-bar app (re-run `/cdt:menubar`, or download the notarized DMG
  from the latest release).
### Packaging
- The **notarized `CDT Usage` DMG** (v1.34.1) is attached to the GitHub release so users can update the
  menu-bar app without rebuilding from source.

## [1.34.0] — 2026-06-16
### Added
- **Automation-first discipline — agents stop inventing manual deploy/build commands.** New
  `automation-first` skill encodes the command hierarchy: **explicit user command > Makefile >
  package/composer scripts > `scripts/` > docs/CI > manual fallback.** Before any build/deploy/run/release
  command, agents inspect the repo and prefer its automation — **Makefile first**; dev deploy/build →
  **`make up-dev`** when present. **Never** run a manual `serverless`/`gradle`/`npm`·`ng build`/`cap
  sync`/AWS·CDK·SAM deploy before checking the Makefile; if a Makefile target **fails, STOP and report** —
  no improvising another path without approval.
  - Wired into the orchestration skill (SKILL.md STEP 3 rule + auto-apply routing table) and **every
    command-running agent** (`backend`/`frontend`/`mobile`/`devops`/`qa`/`data`-engineer — including
    `data`, which runs migrations directly and is a risk-floor category).
  - **Reviewers + QA now flag manual-command usage** when an equivalent Makefile target or repo script
    exists (`code-reviewer`, `security-reviewer` deploy-hygiene, `qa-engineer`).
  - Also added to the global operating summary (`~/.claude/CLAUDE.md`). New `e2e.sh` doc-regression checks.

## [1.33.0] — 2026-06-16
### Added
- **Adaptive advise + ship integration** — Phase 5 (final) of *Parallel Orchestration v2* (all four goals,
  compounding; additive). `cdt-advise "<task>"` now also recommends the **agent mix** — the typical squad
  size (from the tier prior) + the specialists your codebase actually uses (from `agent_runs` telemetry) —
  and points at `cdt-route` for per-agent model sizing. SKILL.md STEP 4 gets a **fast-ship** note: once the
  gate chain is green, flow straight into `/cdt:ship` (or `/cdt:autopilot`) rather than re-litigating done
  work — the verify/scope/memory gates + security veto are the safety net.
- **Parallel Orchestration v2 track complete** (v1.29.0–v1.33.0): fast parallel dispatch · shared-context
  packs · production-grade model right-sizing · quality-via-parallelism · adaptive advise — all additive to
  the baseline, all within bounded dispatch, all above the production-grade model floor. Spec:
  `docs/specs/2026-06-16-parallel-orchestration-v2.md`.

## [1.32.0] — 2026-06-16
### Added
- **Quality-via-parallelism (bounded)** — Phase 4 of *Parallel Orchestration v2* (the quality axis;
  additive). For high-stakes work, CDT now spends a few *extra* parallel agents — ordinary bounded `Agent`
  calls on production models, **never** the Workflow engine — gated by tier + risk + budget:
  - **Adversarial verify** (`/cdt:adversarial`, new command) — 2-3 independent Opus reviewers each try to
    **refute** a risky change/finding; rework if a majority do. Catches plausible-but-wrong work a single
    rubber-stamp pass misses.
  - **Diverse-lens Wave-2 review** — each reviewer takes a distinct lens (correctness · security · perf ·
    a11y/UX) so redundancy can't hide a failure mode.
  - **Design judge-panel** (Wave 0, ambiguous design only) — 2-3 architect variants → judge → synthesize.
  - SKILL.md STEP 3f documents the patterns + their gates; they deepen the Wave-2 review + security veto,
    never replace them. New `e2e.sh` doc-regression checks.

## [1.31.0] — 2026-06-16
### Added
- **Production-grade model right-sizing** — Phase 3 of *Parallel Orchestration v2* (cost + production-grade;
  additive). New `cdt-route "<subtask>"` advises **Opus vs Sonnet** by difficulty signals (risk /
  ambiguity / architecture / review → Opus; substantive build/test/throughput → Sonnet) and **never
  recommends Haiku for substantive work** — only explicitly trivial mechanical ops route to `fast-ops`.
  Cost-effectiveness comes from spending Opus only where it pays, never from a model that can't do the job.
- **Production-grade model floor is now lint-enforced** — `scripts/lint-agents.sh` fails CI if any
  non-`fast-ops` agent is pinned to Haiku (the Sonnet+ floor for substantive agents). SKILL.md model-
  routing section points at `cdt-route`. New `e2e.sh` route assertions + a lint negative test.

## [1.30.0] — 2026-06-16
### Added
- **Shared-context packs (dedup)** — Phase 2 of *Parallel Orchestration v2* (cost + fast shipping;
  additive). Parallel agents used to each re-read the same files — wasted tokens and ramp time. New
  `cdt-context pack <files…>` distills the shared context **once** into a manifest (file list + key
  signatures, language-agnostic) at `~/.claude/.cdt/context/<session>.md`; the orchestrator injects it
  into each Wave-1 agent's READ list (SKILL.md STEP 3) and keeps it as the **stable prompt-cache prefix**
  across the wave. `cdt-context show|path|reset`; stale packs GC'd at SessionStart; pure-shell, fail-open.
  New `e2e.sh` assertions (extracts signatures, omits noise).

## [1.29.0] — 2026-06-16
### Added
- **Fast parallel dispatch** — Phase 1 of the *Parallel Orchestration v2* track (faster shipping +
  cost-effective tokens, **purely additive** — the full baseline flow/agents/skills/gates are untouched).
  - **Budget-elastic fan-out:** `cdt-auto fanout <tier>` recommends how many parallel agents to dispatch
    given remaining weekly headroom — **full tier width when there's room, trimmed toward the floor near
    the ceiling, never below the security-review + qa-verify floor.** More concurrency when affordable
    (faster), trim only *optional* agents when tight.
  - **Worktrees-by-default for parallel multi-writer waves** (≥2 concurrent writers; any T2+ build wave,
    all of T3) so writes truly can't collide and strands run in parallel — `CDT_WORKTREE_DEFAULT=0` to
    force in-place; single-writer waves and T0/T1 stay in-place.
  - **Low-risk fast path:** T0/T1 low-risk changes skip optional Wave-0/Wave-2 agents and ship fast — the
    completion mandate, verify gate, and security review still run.
  - SKILL.md STEP 3 updated; new `e2e.sh` assertions for the fan-out sizing.

## [1.28.0] — 2026-06-16
### Added
- **Cost truthfulness — orchestrator-overhead metering + slice-first as a code gate.** Phase 5 (final) of
  the enforcement track. A new `hooks/usage-lib.sh` centralizes transcript token-summing (reused by the
  per-agent telemetry); at `Stop`, `completion-guard.sh` records the **orchestration overhead** — the
  orchestrator's own tokens vs the work it delegated — to the events DB, and `/cdt:stats` shows it.
- **Slice-first BREADTH is now enforced, not just advised.** `cdt-auto slice record <n>` stamps a token
  baseline; `cdt-auto project <total>` extrapolates per-item cost from a measured slice vs
  `CDT_SCALE_TOKEN_CAP` (`ALLOW`/`STOP`); and `cdt-auto gate scale` now returns **ASK** in auto mode until
  a recent slice baseline exists — so a workflow can't fan out before its cost has been measured.
### Changed
- **README "Why" now documents the enforced-vs-trusted boundary** with a code-backed enforcement table,
  and a design spec lands at `docs/specs/2026-06-16-enforcement-gates.md`. The gates *detect/surface/block*;
  the orchestrator still authors the work — stated plainly rather than over-claimed.
- `hooks/agent-track.sh` refactored to use `usage-lib.sh` (identical token accounting; e2e-verified).

## [1.27.0] — 2026-06-16
### Added
- **Memory gate + smarter recall (fixes "forgets yesterday's lesson").** Phase 4 of the enforcement
  track. Persisting a vault lesson was a prompt-only checklist step; nothing nudged you when it was
  skipped. Now a **team-tier** session (it dispatched ≥1 specialist — solo T0/T1 work is exempt) that
  ended with edits but recorded **no fresh lesson** gets a Stop-time nudge: `cdt-config memory
  warn|block|off` (**default `warn`**). Detected from the state DB (`agent_runs` for the session) + the
  `learnings.md` mtime vs the edit marker; once per session; fail-open.
### Changed
- **`cdt-recall` now re-ranks by recency + outcome, not just lexical overlap.** Among the lessons that
  match a query, newer ones win (exponential decay, ~180-day half-life) and lessons whose terms appear in
  **painful past tasks** (high iterations / blocked, from the `tasks` table) surface first — so hard-won
  lessons rank higher. Still pure-stdlib, grep fallback, fail-open. Weights tunable via
  `CDT_RECALL_RECENCY_WEIGHT` / `CDT_RECALL_OUTCOME_WEIGHT` / `CDT_RECALL_HALFLIFE_DAYS`.

## [1.26.0] — 2026-06-16
### Added
- **Scope/sprawl detection — "exclusive file ownership" is now code-checked (fixes "sprawls a simple
  change into ten files").** Phase 3 of the enforcement track. The contract's exclusive-file scope used to
  be prose only; nothing detected when an agent wrote outside it.
  - A **`PreToolUse(Task)` hook** (`hooks/contract-capture.sh`) records each dispatched agent's contract
    from a `CDT-CONTRACT: exclusive=api/**,server/** ; read=types/**` line the orchestrator now emits
    (SKILL.md STEP 2). Contracts live under `~/.claude/.cdt/contracts/<session>/{pending,claimed}/`.
  - **`SubagentStop`** (`hooks/agent-track.sh`) **atomically claims** the agent's contract (lock-free
    `mv pending→claimed`, safe under concurrent waves) and diffs the files the agent **actually wrote**
    (from its own transcript — attribution works even when parallel agents share one working tree) against
    it. Files outside its scope → **overreach**; files in a peer's scope → **collision**. Recorded to
    `findings.jsonl` + the events DB (`scope_overreach` / `scope_collision`).
  - **Stop gate** surfaces findings: `cdt-config scope warn|block|off` (**default `warn`** — more moving
    parts than the verify gate, so it starts non-blocking). New `cdt-contract` CLI (`add|list|show|
    findings|reset`); stale per-session contracts are GC'd at SessionStart. Glob matching is lenient
    (favours not-flagging). 10 new `e2e.sh` assertions incl. a concurrency double-claim test; fail-open.

## [1.25.0] — 2026-06-16
### Added
- **Grounding is now code-backed — builders carry context7 (fixes "hallucinates APIs").** Phase 2 of the
  enforcement track. The six engineering builders (`backend` / `frontend` / `mobile` / `data` / `devops` /
  `qa`-engineer) were told "context7 first" but didn't actually carry the tools, so they could only guess.
  They now natively carry `mcp__plugin_context7_context7__resolve-library-id` + `…__query-docs` (the two
  doc tools only — least privilege; no web/toolsearch/other-mcp). Their contracts are strengthened to a
  hard "look it up, never use an unfamiliar third-party signature you haven't queried."
- **`lint-agents.sh` locks it in:** check #4 now allows *only* those two context7 tokens for builders
  (any other `mcp__` still fails), and a new check **requires** the six builders to carry both — so
  grounding can't silently regress to "guess APIs". Covered by a new `e2e.sh` assertion.

## [1.24.0] — 2026-06-16
### Added
- **Verification gate — the "gates *force* verification" promise is now code-enforced (on by default).**
  Previously the completion mandate was prompt-only and the optional Stop reminder was off by default, so
  nothing structurally stopped a false "done". Now, if a session **edited files but ran no
  test/build/lint/typecheck afterward**, the `Stop` hook blocks it once with an actionable reason. The
  signal is **marker-based and symmetric with edit tracking** (`hooks/verify-track.sh`, a new PostToolUse
  `Bash` hook, mirrors `format-on-write.sh`'s edit marker), so verifications run **inside a subagent**
  (the qa-engineer flow) count too — `hooks/agent-track.sh` marks the session verified when a subagent's
  transcript shows a verifying command. A main-transcript rescue scan keeps false-positives low; the gate
  **fires at most once per session** and is **fail-open** (no python3/markers → never blocks).
  - Configurable: `cdt-config verify block|warn|off` (default `block`); `CDT_VERIFY_REQUIRE_OUTPUT`
    ignores commands that never actually ran (`command not found`).
  - Verb-anchored allowlist (`hooks/verify-lib.sh`): `pytest`/`jest`/`go test`/`cargo test`/`swift test`/
    `npm test`/`tsc`/`eslint`/`ruff`/`make`/… — never `echo`, `git`, `ls`, `prettier`, `npm install`.
  - Outcomes recorded to the state DB (`events.type = verify_gate`). `validate.sh` now also checks every
    `hooks.json` command path exists and is executable. Covered by 13 new `e2e.sh` assertions.

## [1.23.0] — 2026-06-16
### Added
- **Menu bar now shows your real plan tier** — the `CDT Usage` dropdown header reads
  `Subscription · Max 5x` (or `Pro`, `Free`, …) instead of a bare `Subscription`. 1.22.1 correctly
  noted the `/api/oauth/usage` endpoint carries no plan field, but the tier *is* available locally: the
  Keychain item `Claude Code-credentials` includes `claudeAiOauth.subscriptionType` (`max`/`pro`/…) and
  `rateLimitTier` (e.g. `default_claude_max_5x`, which encodes the 5x/20x multiplier). The app already
  reads that Keychain item for the OAuth token, so this adds **no new network call or permission** — it
  just stops discarding the plan fields. The label is only ever rendered from the real field; an unknown
  tier is title-cased verbatim and a missing one falls back to a neutral `Subscription` (never a guess —
  the rule that drove the 1.22.1 fix still holds). Covered by unit tests on the label mapping
  (`Tests/cdt-menubarTests/PlanLabelTests.swift`).

## [1.22.1] — 2026-06-16
### Fixed
- **Menu bar no longer mislabels the plan as "Claude Max" for Pro users.** The subscription section
  header was hardcoded to "Subscription (Claude Max)", but the `/api/oauth/usage` endpoint returns only
  utilization buckets (`five_hour`, `seven_day`, `seven_day_sonnet`, …) — **no plan/tier field** — so the
  app cannot actually know Pro vs Max. The header is now just "Subscription" (no tier claim); the menu-bar
  doc was reworded to "your real Claude subscription usage". Verified against the live response shape.

## [1.22.0] — 2026-06-16
### Added
- **`/cdt:version`** (and the `cdt-version` CLI) — print the installed version. It reads the canonical
  version from `.claude-plugin/plugin.json` (preferring `CLAUDE_PLUGIN_ROOT`, else the newest cached
  install) and, on macOS, also reports the **menu bar app** version baked into `CDT Usage.app`, flagging
  it as stale when the binary lags the plugin. `cdt-version --short` prints just the version string.
- **Menu bar shows the installed version** — the `CDT Usage` dropdown footer now reads `v<x.y.z> · updated
  <time>`. The Swift app resolves its version from the bundle's `CFBundleShortVersionString` (baked from
  `plugin.json` at build) with a plugin-cache fallback for un-bundled `--once` runs; `cdt-menubar status`
  prints it too.
- `cdt-doctor` now checks `cdt-version` is installed alongside the other CLIs.

### Fixed
- **Menu bar no longer shows frozen subscription %s as if they were live.** The bar reads the Claude
  Code OAuth *access* token from the Keychain; when it expires the usage endpoint returns 401 and the app
  kept displaying the last-good reading silently, so session/weekly % appeared stuck until something
  external (Claude Code / claude.ai) refreshed the Keychain token. Now a stale reading is shown as stale —
  the badge numbers gray out, the dropdown header reads "— stale" with a "⚠ token expired — open Claude
  Code or re-login to refresh (last good <time>)" note — and the failed-fetch retry drops from 5 min to
  **60 s** (escalating 60→120→240→back toward 5 min if the token stays bad) so it self-heals quickly once
  the token is refreshed, without hammering the endpoint (429 still backs off 15 min). The bar relies on
  Claude Code's own token refresh — it re-reads the Keychain every poll. In-app token *minting* was
  evaluated and **deliberately declined**: Claude Code's OAuth refresh token is single-use/rotated, so a
  second app minting from it would invalidate the token Claude Code depends on and log the user out.

## [1.21.2] — 2026-06-15
### Fixed
- **`fast-ops` can now create files from a template** — the agent advertised this but was granted only
  `Edit` (which cannot create new files); added `Write`.
- **State DB no longer drops telemetry under concurrent writes** — `db.sh` sets `busy_timeout` (sqlite3
  CLI) / `connect(timeout=)` (python) so parallel `SubagentStop` waves wait for the lock instead of
  hitting "database is locked" and silently losing the row.
- **`/cdt:notify-setup`** corrected in the env-file template (was a bare `/notify-setup`).

### Hardened (production review)
- **Hooks parse the env file instead of `source`-ing it** (`notify.sh`, `session-start-vault.sh`,
  `completion-guard.sh`) — a value in a hand-edited env can no longer execute. `notify.sh` also validates
  the webhook URL / bot token (rejects quote, backslash, control chars) before it reaches the `curl -K -`
  config line.
- **`statusline.sh`** writes the usage cache atomically (per-PID temp + `os.replace`) so a concurrent
  render can't read a half-written file.
- **`cdt-pr`** reports a clear message when `python3` is absent for `status`/`checks`/`view` (the JSON
  parsers); `diff`/`comment` already degraded cleanly.
- **`code-reviewer`** agent carries an explicit Anti-hallucination section like the builders.
- Independent code review: **APPROVE**; `validate` / `lint-agents` / `e2e` all green.

## [1.21.1] — 2026-06-15
### Fixed
- **Per-agent token telemetry no longer inflated by cache reads.** `agent-track.sh` previously summed
  `input + output + cache_creation + cache_read` into one `tokens` figure — and for a subagent re-reading
  its cached context every turn, `cache_read` dominated by ~100×, making `/cdt:stats`'s "which roles cost
  the most" ranking meaningless (agents showed ~1.1B "tokens"). Now `tokens` is the **cost-relevant** sum
  (`input + output + cache-creation`) and **`cache_read` is a separate column**, shown apart and labeled
  discounted. The ranking now reflects real cost. New `agent_runs.cache_read` column migrates in place;
  e2e asserts the split (fresh vs cache). *(Historical pre-fix rows keep their old combined `tokens` until
  they age out of the today/week windows — the split is forward-looking; counts/roles are unaffected.)*

## [1.21.0] — 2026-06-15
### Added — Autonomous Agent Orchestration (scaling track Phases 2 + 3, as one controller)
- **Autonomous mode router** (in the orchestration skill, STEP 1.5) — after tiering, CDT reads the *work
  shape* and autonomously picks **BOUNDED** (default), **DEPTH** (agent-team Bug Council that debates), or
  **BREADTH** (dynamic-workflow fan-out). Escalation fires only on signature (stuck bug → team; large
  homogeneous set → workflow), always at **xhigh effort, Opus for judgment, never Haiku, never `max`**.
- **Cost governor — `cdt-auto` (+ `/cdt:auto`)** — `status` / `gate <team|scale>` / `explain "<task>"`.
  The orchestrator **must** consult `cdt-auto gate` before any escalation; it returns **ALLOW / ASK /
  DENY** by enforcing the autonomy leash, each engine's on/off, and a **weekly-budget ceiling**. It
  **fails safe** — unknown or stale budget → ASK, never a silent ALLOW (caught in code review).
- **Config plane — `cdt-config autonomy <off|assist|auto>` / `teams <on|off>` / `scale <on|off>`.**
  Default **assist** (auto-summon teams on stuck bugs; propose+ask before a workflow). Engines ship
  **off**; `teams on` sets `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1` (safe nested-`env` merge into
  settings.json); `scale` needs Claude Code ≥ 2.1.154. `cdt-doctor` reports mode + verifies both engines.
- **DEPTH/BREADTH execution protocols** (STEP 3c upgraded, STEP 3e new): teams debate via shared task
  list + mailbox (≤5, time-boxed, then dissolve); workflows are slice-first, contracted, adversarially
  verified, token-capped, with "log what's dropped". Both **fail soft to BOUNDED** if the engine is
  unavailable. The top guardrail now carves the gated Scale-mode exception explicitly.
- Reviewed in Wave 2: **security PASS** (settings.json merge preserves all keys; governor injection-safe),
  **code review** caught + fixed the fail-open governor and a skill contradiction before ship. e2e §9
  covers the full ALLOW/ASK/DENY truth table + the fail-safe + the explain classifier.

## [1.20.0] — 2026-06-15
### Added — Scaling track Phase 1: worktree isolation
- **`cdt-worktree` CLI + `/cdt:worktree` command** — safe git-worktree isolation for parallel work
  (`new` / `list` / `path` / `rm` / `clean`). Each strand gets its own checkout at
  `.claude/worktrees/<name>` on branch `worktree-<name>`, **mirroring Claude Code's `claude --worktree`
  convention** so the two interoperate (same checkout). Turns CDT's disjoint-paths convention into a hard
  filesystem guarantee for big T3 waves / parallel sessions; CDT's HOME-based state means every worktree
  inherits the toolchain for free.
- **Safe by design:** worktree names are validated against path-traversal / option-injection (allowlist),
  removal **refuses a dirty/locked worktree without `--force`** (never a constructed `rm -rf`), and
  `.claude/worktrees/` is auto-added to `.gitignore`. Resolves the **main** worktree via the shared git
  common-dir, so creating a worktree from *inside* a worktree targets the main repo (no nesting).
- **`cdt-doctor`** gains a git/worktree readiness check (+ probes `claude --worktree` support); the
  orchestration skill documents worktree isolation as **opt-in for large parallel work only** (T0–T2 stay
  bounded and in-place). e2e covers create/list/path/reuse/clean + the safety paths (invalid name, dirty
  refusal, force, no-nesting).
- Reviewed in Wave 2: **security PASS** (injection boundary holds), **code review** caught + fixed a
  linked-worktree top-resolution bug before ship.

## [1.19.0] — 2026-06-15
### Added
- **Per-agent token telemetry (P2)** — a `SubagentStop` hook now sums each dispatched subagent's **real**
  token usage straight from its transcript JSONL (`input + output + cache_*`) and stores it on the
  `agent_runs` row; tasks gained a `tokens` column too (`cdt-task … <tokens>`). `/cdt:stats` now ranks
  **which roles cost the most tokens** and shows per-tier token totals — all grounded in actual usage
  rows, never an estimate. Backward-compatible: existing DBs are migrated in place (`ALTER TABLE … ADD
  COLUMN tokens`), and the hook is fail-open (no python3 / unreadable transcript → logs the run with 0).
### CI / quality
- **Agent least-privilege lint (P1)** — `scripts/lint-agents.sh` is now a CI gate. It statically asserts
  every agent's contract can't silently regress: explicit `tools:` allowlist (no implicit "all tools"),
  **no agent may carry `Task`/`Agent`** (no fan-out — only the orchestrator dispatches), read-only agents
  have no `Write`/`Edit`, builders stay within `Read/Grep/Glob/Bash/Write/Edit`, Opus/Haiku pins hold,
  and each agent keeps a `REPORT` section + anti-hallucination language. Runs alongside `validate.sh`.

## [1.18.0] — 2026-06-15
### Security / hardening (full agent-system audit)
- **Least-privilege tools** — the 7 builders (`backend/frontend/mobile/data/devops/qa/diagrams`) now
  declare an explicit `tools:` allowlist (`Read, Grep, Glob, Bash, Write, Edit`) instead of inheriting
  **all tools**. They can no longer spawn subagents (`Task`/`Agent` → cost runaway), `WebFetch`, or
  `NotebookEdit` — only the orchestrator fans out.
- **Anti-hallucination block** added to the 7 agents that lacked it (5 Bug Council + `ui-ux-engineer` +
  `security-reviewer`): ground every claim in real files/output, never fake "done/passing".
- **No same-file collisions** — the contract rule now forbids two agents on the same *file* in one wave
  (e.g. `technical-writer` + `diagrams` on one `.md` run sequentially).
- `ui-ux-engineer` Wave 2 review is now **strictly read-only** (writes only during Wave 0 design).
- `security-reviewer` gains **context7 + WebFetch** to verify CVEs / library security during review.
- `qa-engineer` notes that hard diagnosis warrants Opus / the Bug Council.

## [1.17.1] — 2026-06-15
### Docs
- **README installation overhaul** — a guide-style, production-grade flow: **Step 1 (install, all
  platforms) → Step 2 (per-OS setup) → verify with `/cdt:doctor`**. Separate, collapsible step-by-step
  guides for **macOS / Windows / Linux** (Windows covers Git Bash + the WSL `CLAUDE_CODE_GIT_BASH_PATH`
  pin + the status line). Fixed the cross-links. Written via the new technical-writing discipline.

## [1.17.0] — 2026-06-15
### Added
- **`technical-writer` agent + `technical-writing` skill** — a docs specialist for user-facing
  documentation (README, guides, **release notes**, **CHANGELOG**, **ADRs**, **PR descriptions**). Owns
  `docs/*` prose (not diagram blocks); grounds every claim in real code/output; keeps docs↔reality in
  sync. Wired into Wave 1 (parallel, for user-facing changes) + SKILL routing. Roster is now **14 core
  agents**; **8 quality skills**. (Closes the 'writer' gap vs. the reference architecture; media/video
  intentionally skipped as off-mission.)

## [1.16.0] — 2026-06-15
### Changed
- **Notifications now report the cost of *that task*, not cumulative budget.** The Discord/Telegram
  message shows **tokens used to deliver this task** (an input+output **delta**) and **how long it took**
  — instead of the running session/weekly %. The orchestrator captures a `cdt-tokens` baseline at task
  start and passes the `--tokens`/`--duration` deltas at delivery.
### Added
- **`cdt-tokens`** — prints today's running input+output token total from local transcripts, so a
  per-task cost can be measured as a delta. Pure python3 stdlib.

## [1.15.0] — 2026-06-15
### Changed
- **Plugin renamed to `cdt`** — slash commands are now **`/cdt:*`** (e.g. `/cdt:ship`, `/cdt:doctor`,
  `/cdt:autopilot`) instead of `/claude-dev-team:*`, matching the `cdt-*` CLIs. The marketplace / repo /
  brand stays **claude-dev-team**; install with `claude plugin install cdt@claude-dev-team`. Existing
  installs should reinstall under the new id (`claude plugin uninstall claude-dev-team` → install `cdt`).

## [1.14.0] — 2026-06-15
### Changed
- **Notifications are now rich + detailed.** Discord uses a **colored embed** (green delivered / red
  blocker / …) and Telegram a **formatted HTML** message — each with the **task**, **tier**, **duration**,
  **Task-Loop iterations**, and your current **Max usage %** (session/weekly), plus a timestamp.
  `cdt-notify` gained optional flags (`--task --tier --duration --iters --tokens`); bare
  `cdt-notify TYPE "msg"` still works. The orchestrator fills the fields in automatically. Secrets still
  go to curl via a stdin config; all fields are JSON/HTML-escaped (injection-safe).

## [1.13.0] — 2026-06-15
### Added
- **Two new role agents (Opus)** — completing a product → design → build → review chain:
  - **`product-manager`** (Wave 0, read-only) — turns a vague/user-facing ask into **requirements +
    testable acceptance criteria + scope/non-goals**; its criteria feed the qa tests and the review's
    scope check. Pairs with `superpowers:brainstorming`.
  - **`ui-ux-engineer`** (Wave 0 design + Wave 2 review) — UX flows, **design system/tokens**, and an
    **accessibility (a11y) + visual-polish review**. Owns `design/*`; auto-applies `ui-ux-pro-max` +
    `web-design-guidelines`; the frontend/mobile engineer implements.
  Roster is now **13 core agents** (+ 5 Bug Council). Wired into the Wave 0/Wave 2 flow, SKILL routing,
  the Opus tier, and the team table/diagram. (Memory stays infrastructure; product ownership stays human.)

## [1.12.1] — 2026-06-15
### Changed
- Menu-bar **Eco mode** submenu now labels the default option **"Off (default)"** — uniform with the
  Effort ("Xhigh (default)") and Model ("Opus 4.8 (default)") submenus.

## [1.12.0] — 2026-06-15
### Added
- **Interactive menu-bar controls.** The macOS menu bar dropdown is now a control panel, not just a
  display: an **Enabled** toggle (enable/disable CDT) plus **Eco mode**, **Effort**, and **Model**
  submenus (current value checkmarked). Each selection runs `cdt-config` and the menu refreshes in place.
  effort/model apply next session, as before.
### Changed
- **Eco mode now defaults to `off`** (was `auto`) — full quality by default; opt in with
  `cdt-config eco on|auto`. Keeps Opus/quality the default and only conserves when you choose to.

## [1.11.4] — 2026-06-15
### Added
- **Worked e2e example** in `demo/login-rate-limit/`: a stdlib HTTP API (`api/server.py`, `POST /login`)
  + **6 real end-to-end tests** (`tests/test_e2e.py`) that boot the server on a free port and drive the
  full journey with live `urllib` requests (200 login · 401 wrong/unknown · 429 lockout · 429-while-locked).
  Produced by the orchestrator (backend ∥ qa in parallel; security review PASS). The demo suite is now
  **26 tests** and the e2e runs in CI — a concrete demonstration of the e2e quality gate (v1.11.3).

## [1.11.3] — 2026-06-15
### Changed
- **e2e is now a first-class quality gate.** The qa-engineer's playbook and the orchestration gate chain
  (now **10 gates**, e2e at #6) require **end-to-end tests for user-facing changes** — the real user
  journey via Playwright/Cypress (web), Detox/Maestro (mobile), or supertest/HTTP-flow (APIs), using
  context7 for the framework API and kept deterministic. If a project has no e2e harness, the orchestrator
  proposes one; if e2e can't run, it says so — **never fakes an e2e pass**. (Distinct from `scripts/e2e.sh`,
  which tests this plugin itself.)

## [1.11.2] — 2026-06-15
### Added
- **Committed end-to-end test (`scripts/e2e.sh`) + CI gates.** The e2e runs in a **sandbox** (a throwaway
  temp HOME — never touches your real `~/.claude`) and asserts the full chain: SessionStart bootstrap →
  doctor → deps → learn→recall → task→stats → statusline→budget(eco) → config on/off → notify→log. CI now
  runs **three gates** on every push/PR: `validate.sh`, the demo unit tests, and `e2e.sh`. Documented in
  the README ("How to review / audit") and CONTRIBUTING.

## [1.11.1] — 2026-06-15
### Changed
- **Documentation:** a single, complete **Requirements** section — a per-OS table of every system tool
  (required vs optional), the "no pip packages — python3 stdlib only" note, and the auto-installed
  companion plugins. Added to the table of contents.
- **Eco mode works on macOS out of the box:** the menu bar app now caches each usage fetch to
  `~/.claude/.cdt-usage.json`, so `cdt-budget`/Eco have fresh data without the status line (Windows/Linux
  still use the status line). Verified end-to-end on macOS.

## [1.11.0] — 2026-06-15
### Added
- **Prerequisite installer (`cdt-deps` + `/cdt:deps`)** — checks the system tools CDT uses
  (python3, git, curl, sqlite3, gh) and, with `--install`, installs the missing ones via the detected
  package manager (brew / apt / dnf / pacman / zypper / winget / choco / scoop). Companion **plugins**
  already auto-install via the manifest; scripts use **python3 stdlib only** (no pip packages). First
  session prints a one-line nudge if python3 is missing; `/doctor` points here.
### Changed
- **Cross-platform analytics** — `db.sh` and `cdt-stats` now fall back to **python3's built-in sqlite3**
  when the `sqlite3` CLI is absent (common on Windows), so state logging / stats work everywhere python3
  is present. Independent portability audit across all hooks: **PORTABLE** on macOS / Linux / Windows
  (Git Bash) — every macOS command guarded, `date` has a GNU fallback, all bash-3.2 safe.

## [1.10.1] — 2026-06-15
### Added
- **Windows support** — the orchestration layer (agents, skills, commands, `cdt-*` CLIs, hooks, vault,
  analytics) now runs on Windows. Added `.gitattributes` to **force LF** on shell scripts (CRLF would
  break the bash shebang on Windows checkouts) and a **Windows & Linux** setup section (Git for Windows +
  Python 3; pin `CLAUDE_CODE_GIT_BASH_PATH` if WSL is present; run `/doctor` to verify). The macOS-only
  **menu bar** is skipped on Windows/Linux — use the cross-platform **status line** instead.

## [1.10.0] — 2026-06-15
### Added
- **Budget-aware Eco mode** (`cdt-budget` + `cdt-config eco`) — before a T2+ dispatch the orchestrator
  checks your real weekly usage; when high it **conserves** (prefers Sonnet, smallest safe tier, skips
  optional agents) and says why. Never weakens the risk floor / security review, never uses Haiku for
  real work. Default `auto`.
- **Status line** (`cdt-statusline` + `cdt-config statusline on`) — a terminal status line
  (`CDT on · Opus · xhigh · 41% wk`) that works **cross-platform** (Linux/Windows, no menu bar needed) and
  caches your usage % so Eco mode can read it.
- **`/cdt:doctor`** (`cdt-doctor`) — one-command install health check (hooks, CLIs, DB, gh,
  notifier, menu bar, companion deps) with a fix hint for anything not green.
- **`cdt-learn "<lesson>"`** + `/cdt:learn` — teach the vault a durable lesson on demand
  (surfaced later by `cdt-recall`).

## [1.9.0] — 2026-06-15
### Added
- **`cdt-config` + `/cdt:config`** — a control surface to **enable/disable** the whole
  orchestration layer and set its **defaults (effort, model)**. `off` makes the next session behave as
  stock Claude Code (the SessionStart hook stops injecting the protocol). `effort`/`model` are written to
  `~/.claude/settings.json` as a **safe merge** (all other settings preserved) and apply next session.
  Defaults are **xhigh effort + Opus 4.8** (`claude-opus-4-8`); `max` effort is correctly refused
  (session-only). The menu bar dropdown now shows the current mode (`on · xhigh · opus-4-8`).

## [1.8.1] — 2026-06-15
### Changed
- **Model-routing guardrail hardened** — made explicit everywhere that **Opus is the recommended main
  model**, and that the **low (Haiku) tier is never used for complicated or quality-sensitive work**.
  Strengthened the `fast-ops` agent and the orchestration skill to escalate on anything complicated or
  quality-sensitive (not just "needs judgment"); updated the README routing note to lead with Opus-as-main.

## [1.8.0] — 2026-06-15
### Added
- **PR autopilot (`/cdt:autopilot <PR#>`)** — roadmap **Phase 1**. Drives a real GitHub PR
  toward green: read CI → diagnose → focused fix → push to the branch → re-check (capped by
  `CDT_MAX_ITERATIONS`), resolve merge conflicts on the branch, and post a `code-reviewer` +
  `security-reviewer` synthesis as a PR comment. Backed by `cdt-pr`, a read-mostly `gh` wrapper whose
  only state change is posting a comment.
- **Safe by design:** **dry-run by default** (`--live` to act); **never** force-pushes, auto-merges, or
  closes — merging stays the user's explicit call; security review is mandatory before the "ready"
  verdict; reports each milestone via `cdt-notify`. Requires `gh` authenticated.

## [1.7.0] — 2026-06-15
### Added
- **Adaptive routing (`cdt-advise`)** — roadmap **Phase 3**. Matches a new task against past `tasks`
  history and returns an **advisory** tier/iteration prior (typical tier, iteration budget, blocker
  rate). The orchestration skill consults it on T2+ but still decides — transparent and overridable,
  never a hidden policy. New `/cdt:advise` command. Pure stdlib (python3's built-in
  `sqlite3`), no new dependencies. Adapted from `ruflo`'s trajectory-learning idea, kept on-ethos.

## [1.6.1] — 2026-06-15
### Added
- **Haiku tier (`fast-ops` agent)** — a cheap, fast "hands" tier for **trivial, mechanical,
  fully-specified** operations only (gather/grep/count, literal find-replace, rename, typo, whitespace,
  template fill). **Hard-guarded:** it is never routed orchestration, architecture, development, testing,
  review, security, or debugging — and it escalates the instant a task needs judgment, so the cheap tier
  can't touch quality-critical work. Model routing is now an explicit 3-tier strategy
  (Opus = judgment · Sonnet = throughput/testing · Haiku = trivial ops). Adapted from the tiered-routing
  idea in public agent catalogs, kept on-ethos.

## [1.6.0] — 2026-06-15
### Added
- **Targeted memory recall (`cdt-recall`)** — roadmap **Phase 2, first cut**. Instead of dumping the
  whole learnings file, the orchestrator retrieves only the lessons relevant to the current task via a
  lexically-ranked recall (pure stdlib — **no embedding model or network**). New `/cdt:recall`
  command; the orchestration skill now recalls relevant memory on T2+; the SessionStart hook injects only
  the most recent lessons + a recall pointer. Net effect: **context stays lean and sharp as the vault
  grows** (cost-effective memory that scales).

## [1.5.3] — 2026-06-15
### Docs
- Added **`docs/roadmap.md`** — the phased plan toward a *learning agent network* (autonomous Git/CI/PR
  loop, semantic/RAG memory, adaptive routing, opt-in bounded swarms, federation research), with explicit
  fit/risk/cost notes per phase and the principles that constrain it. Linked from the README.

## [1.5.2] — 2026-06-15
### Docs
- **README polish pass** — added a Table of Contents, a **Troubleshooting** table, a **Security &
  privacy** section, and a dedicated **Uninstall** section; added a PRs-welcome badge.
- **`docs/architecture.md`** — hooks table now includes the `SubagentStop` (`agent-track.sh`) hook and
  the macOS menu-bar auto-install.
- Added **`CONTRIBUTING.md`** and GitHub **issue / PR templates** (`.github/`).

## [1.5.1] — 2026-06-15
### Fixed
- **`db.sh`** flattens newlines/tabs to spaces in stored values (cleaner rows, no smearing); single-quote
  escaping kept, backslashes left intact (SQLite `'…'` literals don't process them).
- **`pkill -f`** in the menu-bar installer now matches the app path literally (dots escaped), so it can't
  over-match an unrelated process.
- **Keychain error** now surfaces the `OSStatus` (via `SecCopyErrorMessageString`), distinguishing a real
  Keychain failure from "not logged in".
- **`RELEASING.md`** documents that the release version comes from `plugin.json`.

## [1.5.0] — 2026-06-15
Production-grade hardening pass (full T3 audit: security, devops, content, native, distribution).
### Security
- **Notifier input validation** — `cdt-setup` now strictly validates every pasted secret
  (Discord webhook / Telegram token / chat id) with whole-string anchoring + a control-char/newline
  reject, closing a shell-injection vector (the env file is `source`d, so a crafted value could have
  executed code on session start).
- **Secrets out of `argv`** — Discord/Telegram URLs are passed to `curl` via a stdin config (`-K -`),
  so tokens are no longer visible in the process list (`ps`/`/proc`).
### Fixed
- **Menu-bar auto-install churn** — guarded on a real success marker instead of a legacy plist that the
  SMAppService path never creates, so the app is no longer killed/relaunched on every session/clear/compact.
- **Retain cycle** in the menu bar's subscription poller (`[weak self]` on the refresh task).
- **CI no longer rots to a green no-op** — installs `shellcheck` + pinned Python explicitly, and
  `validate.sh` now fails (not skips) when `shellcheck` is missing under CI.
- **Docs↔reality** — README project layout lists the `menubar` command; prerequisite bumped to
  Claude Code ≥ 2.1.143 (dependency auto-enable); `menubar` command hint includes `restart`.

## [1.4.8] — 2026-06-15
### Fixed
- Agent-run labels no longer truncate to `claude-dev-team:ba` — the menu bar and `cdt-stats` now strip
  the `claude-dev-team:` namespace prefix and show the bare role (`backend-engineer`, `qa-engineer`, …).

## [1.4.7] — 2026-06-15
### Added
- Menu bar dropdown's **claude-dev-team (7d)** panel now shows **sessions logged** (your chats), so the
  section reflects real activity — not just the rarer specialist-subagent dispatches.
### Changed
- README: menu-bar section + screenshot updated for the stacked **CDT** layout (session % over weekly %).
### Fixed
- No more stray **`unknown`** agent row — the `SubagentStop` hook skips runs with no identifiable agent
  type, **and** the menu bar filters `unknown`/empty rows out at query time, so it never displays even
  if an older in-session hook logged one.

## [1.4.6] — 2026-06-15
### Changed
- Menu bar keeps the **CDT** label, with the stacked session %/weekly % beside it (CDT left, percentages
  stacked right) — branded but still narrow.

## [1.4.5] — 2026-06-15
### Changed
- Menu bar shows the two percentages **stacked** (session % over weekly %, color-coded) as a compact
  rendered image — only as wide as "48%" — so it survives a crowded/notched menu bar. Labels stay in the dropdown.

## [1.4.4] — 2026-06-15
### Changed
- Menu bar strip is now compact (**"CDT 20% 48%"** — session then weekly, color-coded) so it no longer
  crowds out other menu bar items on narrow/notched displays. Session/Weekly labels remain in the dropdown.

## [1.4.3] — 2026-06-15
### Added
- App icon: **CDT Usage.app** now uses the Claude Dev Team logo (`menubar/AppIcon.icns`). README shows the
  logo + a screenshot of the menu bar dropdown. The menu bar itself stays the "CDT <session%> <weekly%>" text.

## [1.4.2] — 2026-06-15
### Fixed
- The menu bar app installs to **/Applications** (was ~/Applications, which isn't where users look),
  falling back to ~/Applications only when /Applications isn't writable. Override with `CDT_MENUBAR_APPS`.

## [1.4.1] — 2026-06-15
### Changed
- Plugin auto-install now builds **CDT Usage.app into ~/Applications** (a real, signed app) instead of a
  bare background binary, and registers login via **SMAppService** so macOS Login Items / Background
  Activity shows **"CDT Usage"** (not the signing team name).
- Menu bar: long resets (weekly) show an absolute time (e.g. **"Fri 1:59 AM"**); short ones stay a
  countdown ("in 3h 18m").
### Fixed
- Agent activity no longer logs **"unknown"** runs (tries agent_type/subagent_type/agent_name, else skips).

## [1.4.0] — 2026-06-15
### Added
- **Notarized-DMG release pipeline** for the menu bar app (`menubar/release.sh` + `Info.plist` +
  `RELEASING.md`). Builds a signed `CDT Usage.app`, notarizes + staples it, and packages a drag-to-
  Applications DMG that opens on any Mac with no Gatekeeper warnings. `--bundle-only` tests the `.app`
  locally with any cert. Requires a Developer ID Application cert + notarytool credentials (Team ID
  XCANJ7SYKG).

## [1.3.4] — 2026-06-15
### Added
- **Code signing.** The menu bar build signs the app with an available identity (Developer ID > Apple
  Development; override via `CDT_SIGN_IDENTITY`). A stable signature makes the macOS Keychain "Always
  Allow" persist across rebuilds (no re-prompt). Builds unsigned — still works locally — if no cert.

## [1.3.3] — 2026-06-15
### Fixed
- **HTTP 429 from the usage endpoint.** Polling was every 60s (too aggressive for the undocumented
  endpoint). Now: subscription %s poll every **5 min** with a **15-min backoff on 429**; local token
  usage still refreshes every 60s. The last good subscription reading stays visible if a refresh fails.

## [1.3.2] — 2026-06-15
### Changed
- Menu bar strip now shows **`CDT <session%> Session  <weekly%> Weekly`** — percentages prominent +
  color-coded, with the `Session`/`Weekly` labels in a small font.

## [1.3.1] — 2026-06-15
### Changed
- Menu bar now shows **`CDT <session%> <weekly%>`** (each % color-coded), instead of a single worst-%.
- Dropdown "updated" time uses **12-hour** format.
- The menu bar app **auto-installs on macOS** on the first session after install (build + launch + login
  auto-start); opt out with `CDT_MENUBAR_AUTO=0`. `cdt-menubar uninstall` is now sticky.

## [1.3.0] — 2026-06-15
### Added
- **macOS menu bar usage monitor** (native Swift, in `menubar/`). Shows your real Claude Max
  subscription usage (session %, weekly %, Sonnet %, reset countdowns — from the `oauth/usage`
  endpoint) **plus** accurate local token usage by model and dev-team activity. `/cdt:menubar`
  builds it, enables auto-start (LaunchAgent), and launches it; `cdt-menubar status` is a no-GUI readout.
  Fail-soft: if the (undocumented) subscription endpoint is unavailable, local data still shows.

## [1.2.1] — 2026-06-15
### Changed
- Analytics framing: "cost" means **token / rate-limit budget** (Claude subscription session + weekly
  limits), **not money** — `/stats` and the orchestrator wording corrected to match Max.

## [1.2.0] — 2026-06-15
### Added
- **Accurate analytics.** A `SubagentStop` hook records every agent dispatch by real `agent_type`, so
  `/stats` shows a true agent-run breakdown. A `cdt-task` CLI logs tier + Task Loop iterations at ship
  (the orchestrator calls it in the completion mandate) → tier mix + average iterations in `/stats`.
### Changed
- `/stats` no longer prints a fabricated cost estimate. Billing defers to Claude Code's live `/cost`
  (on Max, marginal token cost is ~$0); `cdt-stats` reports **activity**, accurately, not billing.

## [1.1.2] — 2026-06-15
### Fixed
- **`cdt-setup --test` now actually sends.** `cdt-notify` was re-sourcing the env file *after* an
  explicit `CDT_NOTIFY_LEVEL=all` override, resetting it to `milestones` (which filters `INFO`), so the
  test was silently dropped. Overrides are now preserved.
### Changed
- `cdt-setup --discord` / `--telegram` are **additive**: configuring a second channel auto-sets
  `provider=both` instead of overwriting the first.

## [1.1.1] — 2026-06-15
### Fixed
- Docs now use the correct **namespaced** slash commands (`/cdt:notify-setup`, etc.) — the
  bare `/notify-setup` form does not resolve.
### Changed
- README Notifications rewritten: leads with the fastest path (`!cdt-setup` wizard), step-by-step Discord
  and Telegram with the right commands.
- `notify-setup` command supports Telegram **token-only** (chat id auto-detected).

## [1.1.0] — 2026-06-15
### Added
- `cdt-setup` **auto-detects your Telegram chat id** from the bot token (via `getUpdates`) — no manual
  chat-id lookup. Works in both flag mode (`--telegram <token>`) and the interactive wizard.
### Changed
- README: **step-by-step** Discord and Telegram notification setup.

## [1.0.0] — 2026-06-15
First production release.
### Added
- **Skill routing** — the orchestrator auto-applies the right quality skill per work-type
  (Web/UI → `ui-ux-pro-max` + `web-design-guidelines`, TS → `clean-code-typescript`,
  debugging → `root-cause-analysis`, simplify → `karpathy-guidelines`, etc.) with no manual invocation.
- **Repo CI** (GitHub Actions) + `scripts/validate.sh`: validates JSON manifests, agent/skill/command
  frontmatter, and shell scripts on every push/PR.
- `CHANGELOG.md`.
### Changed
- `frontend-engineer` and `mobile-engineer` now explicitly auto-apply the UI quality skills.

## [0.2.0] — 2026-06-15
### Added
- **Auto-install companions** — `superpowers`, `code-review`, `frontend-design`, `context7` are declared
  as cross-marketplace dependencies and install automatically with claude-dev-team
  (requires Claude Code ≥ 2.1.110 and the `claude-plugins-official` marketplace).

## [0.1.3] — 2026-06-15
### Fixed
- Grant `context7` access to the read-only `architect` and `pattern-matcher` agents.
- Seed a default notify level so `cdt-setup --show` is never blank.
### Changed
- Flatten the Bug Council agents into `agents/` so all 15 agents register.

## [0.1.0] — 2026-06-15
- Initial release: tech-lead orchestrator, tiered triage, contracts, 10 core + 5 Bug Council agents,
  7 quality skills + orchestration brain, quality gates, Task Loop, completion mandate, SQLite cost
  analytics, Discord/Telegram notifications, and a markdown vault.
