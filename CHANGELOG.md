# Changelog

All notable changes to claude-dev-team. Versions follow semver.

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
