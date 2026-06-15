# Changelog

All notable changes to claude-dev-team. Versions follow semver.

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
