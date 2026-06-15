# Changelog

All notable changes to claude-dev-team. Versions follow semver.

## [1.8.0] — 2026-06-15
### Added
- **PR autopilot (`/claude-dev-team:autopilot <PR#>`)** — roadmap **Phase 1**. Drives a real GitHub PR
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
  never a hidden policy. New `/claude-dev-team:advise` command. Pure stdlib (python3's built-in
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
  lexically-ranked recall (pure stdlib — **no embedding model or network**). New `/claude-dev-team:recall`
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
  endpoint) **plus** accurate local token usage by model and dev-team activity. `/claude-dev-team:menubar`
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
- Docs now use the correct **namespaced** slash commands (`/claude-dev-team:notify-setup`, etc.) — the
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
