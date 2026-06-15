<p align="center">
  <img src="assets/logo.png" alt="Claude Dev Team" width="180">
</p>

# claude-dev-team

> An orchestrated software team for Claude Code. One **tech-lead orchestrator** triages every request,
> writes per-agent **contracts**, dispatches **specialist subagents** in parallel, runs a **quality-gate
> chain**, gets **independent review**, then **ships** — and remembers what it learned.

![license](https://img.shields.io/badge/license-MIT-blue) ![version](https://img.shields.io/badge/version-1.4.5-green) ![claude code](https://img.shields.io/badge/Claude%20Code-plugin-7C3AED) [![validate](https://github.com/jaysonventura/claude-dev-team/actions/workflows/ci.yml/badge.svg)](https://github.com/jaysonventura/claude-dev-team/actions/workflows/ci.yml)

It is built to be **cost-effective on Claude Max while staying high quality**: cheap work stays cheap
(most tasks need no team), and the expensive machinery only engages when complexity or risk demands it.

---

## ✨ What you get

- **Tiered triage (T0–T3)** — trivial edits run solo; features escalate to a parallel team.
- **Contract-driven dispatch** — every agent gets exclusive file ownership, a read-list, a verifiable
  done-condition, guardrails, and a ≤150-word structured report. (This is the anti-hallucination engine.)
- **10 role agents** + a gated **5-agent Bug Council** for stuck bugs.
- **9-gate quality chain** + a bounded **Task Loop** (iterate to green, anti-abandonment, capped, then
  notify).
- **Completion mandate** (tier-scaled) — simplify, review, reuse-audit, dead-code scan, learn, ship.
- **SQLite cost analytics** (`/claude-dev-team:stats`) so you can see and tune spend on Max.
- **Discord / Telegram notifications** for every milestone — delivered, deferred, blocker, ship.
- **A markdown vault** for durable memory (learnings, ADRs, session logs).
- **7 quality skills** (karpathy guidelines, clean TS, code-splitting, gauge-improvements, RCA, web
  design, ui/ux pro-max) plus first-class reuse of the official `superpowers`, `code-review`,
  `frontend-design`, `figma`, and `context7` plugins.

---

## Why

LLM coding fails in predictable ways: it hallucinates APIs, claims "done" without checking, sprawls a
simple change into ten files, and forgets yesterday's lesson. `claude-dev-team` is a **discipline layer**
that fixes those structurally — contracts force grounding, gates force verification, reviewers catch
mistakes, the vault remembers, and tiering keeps it all affordable.

---

## Architecture

How a request flows (Diagram A):

```mermaid
flowchart TD
    U["User request"] --> T["Triage: files + domains + keyword + risk"]
    T --> TIER{"Tier T0-T3"}
    TIER -->|"T0 / T1"| SOLO["Solo / pair"]
    TIER -->|"T2 / T3"| C["Write per-agent contracts"]
    C --> E["Execute: parallel waves"]
    E --> G["Quality gates + Task Loop"]
    G --> R["Independent review + security veto"]
    SOLO --> M["Completion mandate (tier-scaled)"]
    R --> M
    M --> S["Ship"]
    S --> V[("Vault + SQLite")]
    S --> N["Discord / Telegram"]
```

## Execution model

Parallel waves and the quality-gate chain (Diagram B):

```mermaid
flowchart TD
    W0["Wave 0: Explore + architect"] --> W1["Wave 1: builders on exclusive paths"]
    W1 --> GATES["Gates: fmt, lint, type, unit, intg, build, smoke"]
    GATES -->|"fail"| FIX["Fix agent"]
    FIX --> GATES
    GATES -->|"pass"| W2["Wave 2: code-reviewer + security-reviewer"]
    W2 -->|"security risk >= medium"| VETO["VETO: block ship"]
    W2 -->|"pass"| DONE["Proceed to completion mandate"]
```

## Triage & tiers

`complexity = files + domains + keyword + risk`. Anything touching **auth, payments, infra, migrations,
or secrets** is force-escalated to **T2+** and gets the full mandate (the *risk floor*).

| Tier | Name | Agents | When |
|------|------|--------|------|
| **T0** | solo | 0 | one file, one domain, no risk |
| **T1** | pair | 0–1 | small single-domain change |
| **T2** | squad | 3–5 | multi-domain, or any risk |
| **T3** | full | 6–10 | large / cross-cutting feature |

Tier decision (Diagram C):

```mermaid
flowchart TD
    A["Task"] --> RISK{"auth / payments / infra / migrations / secrets?"}
    RISK -->|"yes"| T2["T2+ forced"]
    RISK -->|"no"| SZ{"files and domains"}
    SZ -->|"1 file, 1 domain"| T0["T0 solo"]
    SZ -->|"small, 1 domain"| T1["T1 pair"]
    SZ -->|"multi-domain"| T2b["T2 squad"]
    SZ -->|"large / cross-cutting"| T3["T3 full"]
```

**Overrides you can type:** `T0:` forces solo/cheap · `FULL:` forces full-Opus + all gates for critical
work (raises model + gates only — never effort or engine).

## The team

Orchestrator, specialists, and skills (Diagram D):

```mermaid
flowchart LR
    O(("Orchestrator")) --> RES["architect / Explore"]
    O --> BUILD["backend / frontend / mobile / data / devops / qa"]
    O --> REV["code-reviewer / security-reviewer"]
    O -.->|"stuck bug"| BC["Bug Council x5"]
    O --> SK["skills: karpathy, clean-ts, code-splitting,<br/>gauge, rca, web-design, ui-ux"]
```

| Agent | Model | Role / file scope |
|-------|-------|-------------------|
| `architect` | Opus | design, interfaces, contracts (read-only) |
| `backend-engineer` | inherit | APIs, server, data access, logic (`api/server/*`) |
| `frontend-engineer` | inherit | web UI/components (`ui/client/*`) |
| `mobile-engineer` | inherit | RN/Expo/Flutter/native (`mobile/app/*`) |
| `qa-engineer` | inherit | tests + the gate chain (`test/*`) |
| `code-reviewer` | Opus | independent correctness/scope review (read-only) |
| `security-reviewer` | Opus | security review with **veto** (read-only) |
| `devops-engineer` | inherit | CI/CD, Docker, infra (`ci/* infra/*`) |
| `diagrams` | inherit | mermaid / figma visuals |
| `data-engineer` | inherit | schema, migrations, queries (`db/*`) |
| **Bug Council** (gated ×5) | inherit | root-cause-analyst · code-archaeologist · pattern-matcher · systems-thinker · adversarial-tester |

**Model routing is the core cost lever:** Opus reasons & reviews; Sonnet does the bulk typing. Run a
Sonnet session for routine work; `FULL:` or `/model opus` for critical work.

## Skills

| Skill | Use it for |
|-------|-----------|
| `orchestration` | the whole workflow (auto-triggers on dev tasks) |
| `karpathy-guidelines` | simplicity-first engineering bar |
| `clean-code-typescript` | strict, readable TS |
| `code-splitting` | file/module/bundle boundaries |
| `gauge-improvements` | prove a change is actually better |
| `root-cause-analysis` | debug to the cause, not the symptom |
| `web-design-guidelines` | UI fundamentals + a11y |
| `ui-ux-pro-max` | polish, motion, micro-interactions |

Reused official plugins: `superpowers`, `code-review`, `frontend-design`, `context7` — these
**auto-install as dependencies** when you install claude-dev-team (see Installation). `figma` is optional.

## Commands

Plugin commands are **namespaced** — invoke them as `/claude-dev-team:<command>` (auto-loaded in a fresh
session; the bare `/command` form won't match).

| Command | Does |
|---------|------|
| `/claude-dev-team:triage <task>` | preview the tier + proposed dispatch **without** executing |
| `/claude-dev-team:ship` | run the completion mandate on the current work and ship |
| `/claude-dev-team:bug-council <symptom>` | convene the 5-agent diagnostic squad |
| `/claude-dev-team:stats [today\|week\|all]` | cost & activity report from the state DB |
| `/claude-dev-team:notify-setup [...]` | configure Discord/Telegram (no manual `.env`) |
| `/claude-dev-team:menubar [install\|status\|...]` | macOS menu bar usage monitor (subscription % + local tokens) |

---

## Installation

**Prerequisites:** Claude Code **≥ 2.1.110**; `git`; macOS/Linux; and the official marketplace
registered (it ships by default — if not, `claude plugin marketplace add anthropics/claude-plugins-official`).

**Install this plugin** — the companions (`superpowers`, `code-review`, `frontend-design`, `context7`)
**auto-install** as dependencies:
```
claude plugin marketplace add jaysonventura/claude-dev-team
claude plugin install claude-dev-team
```
Install **auto-enables** the plugin (and its companions) — no manual enable step. It's a **user-scope**
install in `~/.claude/`, so it works automatically across **every Claude Code surface** on this machine —
the CLI, the VS Code & JetBrains extensions, and the Claude desktop app all share that same config (agents,
skills, commands, hooks, and the orchestration `CLAUDE.md`). Non–Claude-Code agents (e.g. Google
Antigravity) run a different engine and won't load it.

**After install → just prompt (zero config).** Restart your Claude Code session (or `/reload-plugins`)
once so it loads. From then on, describe any task normally — the `orchestration` skill auto-triggers,
the SessionStart hook bootstraps `~/.claude/vault/` + the SQLite DB + the `~/.claude/bin/` CLIs, skills
auto-apply, and the `/claude-dev-team:*` commands (`ship`, `triage`, `bug-council`, `stats`) are
available. Nothing else to set up.

- **Notifications are optional** — run `/claude-dev-team:notify-setup` only if you want Discord/Telegram pushes.
- **Power-user (guaranteed every session):** installers get orchestration via the auto-triggering skill
  + hook. For a hard always-on guarantee, drop the `orchestration` summary into your global
  `~/.claude/CLAUDE.md` (see `docs/architecture.md`). Most users don't need this.

---

## Notifications (Discord + Telegram)

Milestones (`DELIVERED` / `DEFERRED` / `BLOCKER` / `SHIP`) are logged to the vault and pushed to your
channel(s). Secrets live in `~/.claude/claude-dev-team.env` (`chmod 600`, **never committed**) — you
never hand-edit them.

**⚡ Fastest path — the wizard** (hidden input for tokens):
```
!~/.claude/bin/cdt-setup
```
Pick Discord / Telegram / Both, paste the secret; it auto-detects the chat id and auto-tests. Done.

> 💡 The `!` prefix runs a command from **inside Claude Code's input box**. In a **plain terminal**,
> drop the `!` (zsh reads a leading `!` as history expansion → `event not found`). Use the full path
> either way: `~/.claude/bin/cdt-setup …`

Prefer a single command? Use the slash command **`/claude-dev-team:notify-setup`** (all plugin commands
use the `/claude-dev-team:` prefix), or the `cdt-setup` CLI directly.

### Discord — step by step
1. In Discord: **Server Settings → Integrations → Webhooks → New Webhook**.
2. Pick a channel, click **Copy Webhook URL**.
3. Configure it (one line):
   ```
   /claude-dev-team:notify-setup discord https://discord.com/api/webhooks/XXXXXX/YYYYYY
   ```
   …or via CLI: `!~/.claude/bin/cdt-setup --discord "<url>"`
4. A test message lands in that channel. Done.

### Telegram — step by step
1. In Telegram, open **@BotFather** → send `/newbot` → follow prompts → **copy the bot token**
   (looks like `123456789:AA...`).
2. **Open your new bot and send it any message** (e.g. `hi`). *(Required — the bot can only find your
   chat id after you message it first.)*
3. Configure it — the chat id is **auto-detected** from the token, so you don't need to find it:
   ```
   /claude-dev-team:notify-setup telegram <your-bot-token>
   ```
   …or via CLI: `!~/.claude/bin/cdt-setup --telegram <your-bot-token>` → `Telegram saved (chat id: …)`
4. Send a test: `!~/.claude/bin/cdt-setup --test` → you should get a Telegram message.

### Settings
`CDT_NOTIFY_PROVIDER` = `discord` | `telegram` | `both` | `off` · `CDT_NOTIFY_LEVEL` = `all` |
`milestones` | `off`. Credentials live in `~/.claude/claude-dev-team.env` (`chmod 600`, **never
committed**). A posted message looks like:
`✅ [DELIVERED] /login endpoint shipped: rate-limited, 12 tests green`.

---

## Usage examples

Just describe the task — the orchestrator triages and runs the right amount of process.

- **T0 — "fix this typo in the README"** → stays solo, edits, verifies, ships. One model call.
- **T2 — "add a rate-limited `/login` endpoint with tests"** → risk floor forces T2+: `architect`
  designs the interface, `backend-engineer` implements (`api/*`), `qa-engineer` writes tests (`test/*`),
  gates run, `security-reviewer` checks the auth path, then ship + a Discord post.
- **T3 — "build a settings page (web + mobile) with API + a migration"** → full team in parallel waves:
  architect → backend + frontend + mobile + data (exclusive paths) → gates + Task Loop → code + security
  review → ship + vault learning.

T2 example as a sequence (Diagram E):

```mermaid
sequenceDiagram
    participant U as User
    participant O as Orchestrator
    participant A as architect
    participant B as backend-engineer
    participant Q as qa-engineer
    participant S as security-reviewer
    participant N as cdt-notify
    U->>O: add rate-limited /login with tests
    O->>A: contract - design auth + interfaces
    A-->>O: interfaces + file plan
    O->>B: contract - implement api/*
    O->>Q: contract - tests test/*
    B-->>O: done + evidence
    Q-->>O: gates green
    O->>S: security review (risk floor)
    S-->>O: PASS
    O->>N: SHIP digest
    O-->>U: shipped
```

---

## Autonomy & debugging

**Task Loop** — bounded autonomous quality enforcement (Diagram F):

```mermaid
stateDiagram-v2
    [*] --> Build
    Build --> Gates
    Gates --> Pass: all green
    Gates --> Fix: failure
    Fix --> Gates: re-run
    Gates --> Stuck: same failure twice
    Stuck --> BugCouncil
    BugCouncil --> Gates
    Fix --> Cap: hit CDT_MAX_ITERATIONS
    Cap --> Notify: BLOCKER / DEFERRED
    Pass --> [*]
    Notify --> [*]
```

**Bug Council** — convened only when stuck (Diagram G):

```mermaid
flowchart TD
    BUG["Stuck bug"] --> O(("Orchestrator"))
    O --> RCA["root-cause-analyst"]
    O --> ARCH["code-archaeologist"]
    O --> PM["pattern-matcher"]
    O --> ST["systems-thinker"]
    O --> AT["adversarial-tester"]
    RCA --> SYN["Synthesize: ranked root cause + fix plan"]
    ARCH --> SYN
    PM --> SYN
    ST --> SYN
    AT --> SYN
    SYN --> ENG["Engineer implements fix"]
```

Anti-abandonment: agents must emit a structured `BLOCKER` rather than quit or fake success. The loop
stops after `CDT_MAX_ITERATIONS` (default 5) and notifies you — protecting your Max rate limits.

---

## State & cost analytics

A local SQLite DB (`~/.claude/claude-dev-team.db`) records `sessions`, `tasks`, `agent_runs`, `events`,
and `usage`. Run `/claude-dev-team:stats` (or `cdt-stats today|week|all`) for activity by tier/agent,
iteration counts, and blocker rate. Activity/timing is precise. "Cost" here means **token / rate-limit
budget** (Claude subscription session + weekly limits, not money); for exact tokens used, see Claude
Code's `/cost`.

## Menu bar usage monitor (macOS)

A native Swift app (`menubar/`) puts your usage in the menu bar as **`CDT <session%> <weekly%>`** (each
% color-coded 80/90) — the **real subscription %** (current session, weekly all-models, weekly Sonnet,
with reset countdowns) from Anthropic's `oauth/usage` endpoint, **plus** accurate local token usage by
model and dev-team activity in the dropdown.

<p align="center">
  <img src="assets/menubar-screenshot.png" alt="CDT Usage menu bar dropdown" width="440">
</p>

**On macOS it auto-installs** on your first session after the plugin is installed — it builds, launches,
and enables login auto-start automatically (set `CDT_MENUBAR_AUTO=0` in `~/.claude/claude-dev-team.env`
to opt out). Manage it any time:

```
!~/.claude/bin/cdt-menubar status      # one-shot terminal readout, no GUI
/claude-dev-team:menubar restart       # or: install | start | stop | uninstall
```

Requires macOS + the Swift toolchain (`xcode-select --install`); first launch shows a one-time Keychain
approval (**Always Allow**). The subscription %s use an **undocumented** endpoint (the same one Claude
Code calls) and may change — it **fails soft**, and your local token data always works. `cdt-menubar
uninstall` removes the login item + binary (and stops auto-reinstall).

**Distributing a prebuilt app:** the build auto-signs with any available code-signing identity. To ship a
**notarized DMG** that opens on any Mac with no Gatekeeper warnings (drag to Applications, like an App
Store app), see [`menubar/RELEASING.md`](menubar/RELEASING.md) — it needs a Developer ID Application
certificate + `notarytool` credentials, then `cd menubar && ./release.sh`.

## Configuration

| Setting | Default | Meaning |
|---------|---------|---------|
| session model | your choice | Sonnet = cheap throughput; Opus = max power |
| `FULL:` / `T0:` prefixes | — | up/down-throttle a single request |
| `CDT_MAX_ITERATIONS` | 5 | Task Loop hard cap |
| `CDT_NOTIFY_PROVIDER` | off | `discord` / `telegram` / `both` / `off` |
| `CDT_NOTIFY_LEVEL` | milestones | `all` / `milestones` / `off` |
| `CDT_STOP_REMINDER` | 0 | `1` = remind once to run the mandate at session end |

Effort runs at your session level and the orchestration never uses heavy multi-agent fan-out engines —
it dispatches a bounded set of subagents per tier. Pin any agent's `model:` in `agents/*.md` to taste.

## How to review / audit

Everything is plain files. Check: agents honoring exclusive scope (the diffs), gates actually run
(pasted output in reports), `~/.claude/vault/` session notes + learnings, `status-log.md`, and the DB
(`/claude-dev-team:stats`). To uninstall, `claude plugin uninstall claude-dev-team` and remove the orchestration block
from `~/.claude/CLAUDE.md` — you're back to stock Claude Code.

## Project layout

```
.claude-plugin/   plugin.json, marketplace.json
agents/           10 core role agents + 5 Bug Council agents (flat)
skills/           orchestration (brain) + 7 quality skills
commands/         ship, triage, bug-council, stats, notify-setup
hooks/            hooks.json + scripts (vault/db/format/notify/setup/stats/guard) + vault-template
docs/             architecture.md, examples.md
```

## Roadmap & contributing

More agents (`pm`, `technical-writer`, `ml-engineer`); a measured roster expansion (SRE, accessibility,
performance auditor); media/writing skills; an opt-in Eco mode; richer cost attribution. To add an
agent, drop a markdown file in `agents/`; to add a skill, a folder + `SKILL.md` in `skills/`. PRs welcome.

## License

MIT © 2026 Jayson Ventura.
