# Architecture deep-dive

`claude-dev-team` is a **discipline layer** over Claude Code. The orchestrator (the main agent, guided by
the `orchestration` skill) never rushes to code — it runs a four-step lifecycle and delegates
implementation to specialist subagents under strict contracts.

## The four steps

1. **Triage** — score `files + domains + keyword + risk`; pick a tier (T0–T3); a risk floor force-escalates
   anything touching auth/payments/infra/migrations/secrets. On T2+, read the vault.
2. **Contract** — each dispatched agent gets: types/signatures · exclusive file ownership · files-it-may-
   read · a verifiable DONE-WHEN · DO-NOT guardrails · a ≤150-word structured report. Exclusive ownership
   means parallel agents never collide; the read-list + grounding rules kill hallucination.
3. **Execute** — parallel waves (research → build → review) with a 9-gate quality chain and a bounded Task
   Loop between them. Security review holds a veto.
4. **Completion mandate** — tier-scaled close (simplify → review → reuse-audit → dead-code → vault-learning
   → ship), full on T2/T3 and all risk work.

## Why it's cost-effective and high quality at once

- **Tiering** means most tasks (T0/T1) cost a single call; you only pay for orchestration when warranted.
- **Model routing (3 tiers)** spends Opus only on judgment (architect, reviewers), Sonnet on throughput
  (builders, tests, orchestration), and Haiku (`fast-ops`) only on *trivial mechanical* ops — which
  escalates the moment a task needs judgment, so the cheap tier never touches quality-critical work.
  Output stays high quality because Opus reviews everything.
- **Contracts** cap tokens per agent (no whole-repo reads, no rambling).
- **Bounded autonomy** (Task Loop cap, gated Bug Council) prevents runaway spend.
- Effort stays at your session level; the orchestrator uses ordinary bounded subagent dispatch and
  **never** the heavy multi-agent fan-out engines.

## Dual delivery

- **Plugin (everyone):** agents, skills, commands, and hooks ship in this repo; the `orchestration` skill
  auto-triggers. Hooks use `${CLAUDE_PLUGIN_ROOT}` and bootstrap per-user state into `~/.claude/`.
- **Always-on (you):** add the orchestration summary to your global `~/.claude/CLAUDE.md` so the behavior
  is guaranteed every session, not just when the skill triggers.

### Suggested `~/.claude/CLAUDE.md` activator

```md
# Operating mode — tech-lead orchestrator (claude-dev-team)
For any non-trivial software task, invoke the `orchestration` skill and follow it:
triage (T0–T3, risk floor) -> contract -> dispatch specialists -> quality gates -> review ->
tier-scaled completion mandate -> ship. Never claim done without running the verifying command and
pasting output. Library/API questions -> context7 first. Report milestones via
~/.claude/bin/cdt-notify. Effort stays xhigh; never use heavy fan-out engines.
```

## Hooks

| Event | Script | Effect |
|-------|--------|--------|
| SessionStart | `session-start-vault.sh` | bootstrap vault + DB + `~/.claude/bin/*`; inject learnings; auto-install the menu bar (macOS, once) |
| PostToolUse (Edit/Write) | `format-on-write.sh` | guarded prettier (only if configured) + edits marker |
| SubagentStop | `agent-track.sh` | record each dispatched subagent by role (powers the `/stats` agent-run breakdown) |
| Stop | `completion-guard.sh` | record session row; optional one-time mandate reminder (`CDT_STOP_REMINDER=1`) |

All hooks are **fail-open** — any error exits 0 so they never interrupt your session.

## Memory (vault + recall)

Durable memory lives in `~/.claude/vault/` as plain markdown — `learnings.md` (curated lessons),
`sessions/` (per-task notes), `adrs/`, `log.md`, `status-log.md`. The completion mandate appends a lesson
after meaningful work. To keep context **cost-effective as the vault grows**, memory is *retrieved, not
dumped*: SessionStart injects only the most recent lessons, and on T2+ the orchestrator runs
`cdt-recall "<task>"` to pull just the lessons relevant to the current task (lexical ranking, pure stdlib —
no embedding model or network). See `docs/roadmap.md` Phase 2 for the planned semantic upgrade.

## State DB schema

`sessions(id,cwd,started,ended,tier,outcome)` · `tasks(session_id,description,tier,status,iterations,
started,ended)` · `agent_runs(task_id,agent,model,started,ended)` · `events(ts,session_id,type,message)`
· `usage(session_id,ts,est_tokens,est_cost)`.
