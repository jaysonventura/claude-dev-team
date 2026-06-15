# Spec — claude-dev-team Menu Bar Usage Monitor (macOS, native Swift)

Date: 2026-06-15 · Status: approved-pending-review

## Context & goal

Ship a macOS **menu bar app** as part of `claude-dev-team` so a Claude Max user can monitor usage in
real time from the system status area: the real **subscription limits** (current session %, weekly
all-models %, weekly Sonnet %, with reset countdowns — like Claude.ai's "Plan usage limits" panel)
**and** the local **token usage + dev-team activity** that `claude-dev-team` already tracks.

## Data sources (verified)

- **#1 Subscription usage (real, undocumented):** `GET https://api.anthropic.com/api/oauth/usage` with
  `Authorization: Bearer <token>`, where `<token>` is read from the macOS Keychain item
  **`Claude Code-credentials`** (the same one Claude Code stores). Returns the session/weekly buckets +
  reset times. **This endpoint is undocumented and may change** — the app degrades gracefully if it
  fails (see Error handling). This is the only source for the official %; there is no supported API.
  (Pattern confirmed by the public `adntgv/claude-usage-systray`.)
- **#2 Local token usage (accurate, supported):** `~/.claude/projects/*/*.jsonl` transcripts carry
  per-message `usage` (input/output/cache tokens + `model`). Aggregate by 5h window / today / week.
- **#2 Dev-team activity:** `~/.claude/claude-dev-team.db` (sessions, events, agent_runs by role,
  tasks by tier) — already populated by the plugin's hooks/CLIs.

## Architecture (Swift Package, `menubar/`)

Small, single-purpose units:
- **`KeychainReader`** — reads `Claude Code-credentials` via the Security framework; returns the OAuth
  token (or nil). No token caching to disk.
- **`UsageAPIClient`** — calls `/api/oauth/usage`; decodes session/weekly buckets + resets into
  `SubscriptionUsage`. Returns `.failure` on 401/network/decode (never throws to UI).
- **`LocalUsageReader`** — scans the JSONL transcripts (incrementally, by mtime) → `LocalUsage`
  (tokens by model for window/today/week); reads the SQLite DB → `TeamActivity` (agent runs, tiers).
- **`UsageStore`** — merges into one `UsageSnapshot`; published to the UI; holds last-good values.
- **`Poller`** — `Timer`: refresh #1 every ~60s, #2 every ~30s (cheap, incremental). Backs off on
  repeated #1 failures.
- **`MenuBarController`** — owns the `NSStatusItem`: compact title (worst-window %, color-coded
  orange ≥80 / red ≥90; falls back to a token figure if #1 unavailable) + a dropdown menu rendering
  the full breakdown, countdowns, "Open /usage docs", "Refresh", "Quit".
- **`main.swift`** — `NSApplication` as accessory (`LSUIElement`), wires the above, starts the poller.

## UI

- **Menu bar (compact):** e.g. `▓ 66%` colored by the worst of {session, weekly}. If #1 is unavailable:
  show a local token figure (e.g. `2.1M ⏱`) so it's never blank.
- **Dropdown:**
  - *Subscription* — Session 66% · resets in 33m │ Weekly (all) 46% · resets Fri 1:59a │ Sonnet 2%
    (each a labeled bar). If unavailable: "Subscription data unavailable (endpoint/login)".
  - *This session (local)* — tokens by model (Opus/Sonnet/Haiku in/out/cache); agent runs by role;
    tasks by tier.
  - *Footer* — last-updated time · Refresh · Open Claude usage · Quit.

## Packaging & install

- **`menubar/Package.swift`** — executable target `cdt-menubar` (SwiftPM, no Xcode project; builds with
  `swift build -c release`).
- **`hooks/menubar-install.sh` → `~/.claude/bin/cdt-menubar`** — `build` (swift build), `start`,
  `stop`, `status`, `install-login` (write a LaunchAgent plist to
  `~/Library/LaunchAgents/com.jaysonventura.claude-dev-team.menubar.plist` → auto-start at login),
  `uninstall` (remove LaunchAgent + binary). **Auto-start LaunchAgent: yes** (default on install).
- **`commands/menubar.md` → `/cdt:menubar`** — drives the installer (build + start +
  install-login) and reports status.
- **README + CHANGELOG** — document install, the undocumented-endpoint caveat, and Quit/uninstall.
- Requires: macOS, Swift toolchain (`swift` / Xcode CLT). The installer checks and instructs if missing.

## Error handling (fail-soft, never crash)

- No Swift toolchain → installer prints the one-line fix (`xcode-select --install`).
- No Keychain token / not logged in / 401 / network error / schema change in #1 → hide the subscription
  section (or show "unavailable"), keep showing #2. Exponential backoff on #1; recover automatically.
- No transcripts or DB → show whatever is available; never blank.
- Endpoint shape changes → decode failure is caught; #1 shows unavailable; #2 unaffected.

## Verification

1. `swift build -c release` succeeds; `cdt-menubar start` shows an icon in the menu bar.
2. With Claude logged in: subscription %s match `/usage` (±rounding); resets count down.
3. Token-by-model totals reconcile against a manual sum of a known transcript.
4. Kill network → subscription section shows "unavailable", #2 still updates, recovers when back.
5. `install-login` → app relaunches after logout/login; `uninstall` removes the LaunchAgent + binary.
6. Privacy: token is only sent to `api.anthropic.com`; never written to disk/logs.

## Out of scope (v1)

Windows/Linux; historical charts; notifications/alerts on threshold; configurable thresholds (hardcode
80/90 first); per-project breakdown.

## Risks

- **Undocumented endpoint** may change/break → mitigated by fail-soft (#2 always works) + documented caveat.
- **ToS gray area** (OAuth token used by a non-official client) → it's the user's own account/data, each
  installer uses their own token, mirroring an existing public tool; documented honestly.
