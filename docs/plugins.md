# Plugin bootstrap & routing

CDT ships knowing the official Claude Code companion plugins **as data**. A verified registry
(`config/plugins.json`) is the single source of truth for **detection, health, routing, and conflict
rules** — so CDT can tell you which plugin fits a task, whether it's healthy, install/enable it through the
real `claude plugin` CLI, and never let a plugin front-run its own agents.

It is also the **bundle manifest**: one `claude plugin install cdt` brings the whole toolchain (see
[All-in-one install](#all-in-one-install)). **Detection stays read-only and idempotent**, every
install/enable/update is shelled out to Claude Code's own CLI, and there is deliberately **no destructive
`uninstall`** and **no auto-authentication**.

- Registry: [`config/plugins.json`](../config/plugins.json)
- CLI: `~/.claude/bin/cdt-plugins` (`/cdt:plugins`) — from `hooks/plugins.sh`
- Advisory router: `~/.claude/bin/cdt-plugin-route` — from `hooks/plugin-route.sh`
- Shared detection library (frozen, sourced): `hooks/plugins-lib.sh`
- Verified against the `claude plugin` CLI on **Claude Code 2.x** (2.1.207 at time of writing).

---

## All-in-one install

A single `claude plugin install cdt@claude-dev-team` lands **the whole toolchain**. Nothing here is opt-in.

| What | How it arrives |
|------|----------------|
| 13 skills · 19 agents · 21 commands | bundled inside the plugin — always present |
| `sequential-thinking` MCP | shipped `.mcp.json`, auto-registers |
| **12 official plugins** — superpowers, code-review, frontend-design, context7, playwright, github, sentry, terraform, laravel-boost, typescript/php/swift LSP | `plugin.json` `dependencies` — Claude Code resolves, installs and enables them |
| **2 community plugins** — ponytail, claude-mem | **SessionStart bootstrap** (`cdt-plugins bootstrap`) |

### Why the community plugins need a bootstrap

They cannot be manifest dependencies. Claude Code leaves *"dependencies from a marketplace you have not
added unresolved"*, and **disables the dependent plugin** until the error is resolved — and it never
auto-adds a marketplace. Declaring `ponytail` or `claude-mem` in `dependencies` would therefore **disable
CDT itself** on every machine that lacks the `ponytail` / `thedotmack` marketplaces. The bootstrap does the
`marketplace add` first, then the install, so the bundle is complete without that failure mode.

The bootstrap is **idempotent** (a stamp at `~/.claude/.cdt/bootstrap-community.done`, plus a live
installed-state check so an uninstall re-heals), **fail-open** (always exits 0 — a bootstrap problem can
never break your session), **bounded** (`CDT_BOOTSTRAP_TIMEOUT`, default 180s per shell-out), **async** (it
never delays startup), and **redacted**. New plugins load after a restart.

```bash
~/.claude/bin/cdt-plugins bootstrap          # run it by hand
~/.claude/bin/cdt-config bootstrap-community off   # opt out entirely
```

### What still is not automatic

CDT installs plugins; it cannot provision external toolchains or credentials. These stay
warn-with-remediation:

| Not auto-provisioned | Why | You run |
|---|---|---|
| `typescript-language-server`, `intelephense`, `sourcekit-lsp` | language servers are npm/system packages | the install shown in the health table |
| Playwright browsers | ~400MB download | `npx playwright install` |
| `bun`, `uv` (claude-mem) | claude-mem self-installs them on first worker start | nothing — it handles it |
| `github` / `sentry` auth | OAuth is interactive; **CDT never authenticates for you** | `/mcp` |

So a fresh machine legitimately shows a few `⨯ missing-dep` and `! needs-auth` rows until you run those.
`cdt-plugins doctor` still exits **0** — only the four *required* plugins can fail it.

> **Cost warning.** This bundle now installs `claude-mem` on every new machine. Its `PostToolUse` hook fires
> on **every tool call** and each observation is a Claude Agent SDK completion billed to **your** usage
> budget. See the cost note under [Community plugins](#community-plugins) to redirect it to a separate
> backend, or run `cdt-config bootstrap-community off` before first launch.

---

## The registry (single source of truth)

`config/plugins.json` lists **15 plugins**. Every install identifier is real — `<name>@claude-plugins-official`
for the official rows, `ponytail@ponytail` and `claude-mem@thedotmack` for the two community rows;
`ui-ux-pro-max` is a CDT-local skill with **nothing to install** (`installIdentifier: null`).

| id | Type | Install identifier | Default-on | Scope | Auth | Security |
|----|------|--------------------|:----------:|-------|:----:|----------|
| `superpowers` | claude-code-plugin | `superpowers@claude-plugins-official` | yes | user | — | official |
| `code-review` | claude-code-plugin | `code-review@claude-plugins-official` | yes | user | — | official |
| `frontend-design` | claude-code-plugin | `frontend-design@claude-plugins-official` | yes | user | — | official |
| `context7` | mcp-plugin | `context7@claude-plugins-official` | yes | user | — | official |
| `typescript-lsp` | lsp-plugin | `typescript-lsp@claude-plugins-official` | yes | project | — | official |
| `php-lsp` | lsp-plugin | `php-lsp@claude-plugins-official` | yes | project | — | official |
| `swift-lsp` | lsp-plugin | `swift-lsp@claude-plugins-official` | yes | project | — | official |
| `playwright` | mcp-plugin | `playwright@claude-plugins-official` | yes | project | — | official |
| `github` | mcp-plugin | `github@claude-plugins-official` | yes | user | **yes** | verified-third-party |
| `sentry` | mcp-plugin | `sentry@claude-plugins-official` | yes | user | **yes** | verified-third-party |
| `terraform` | claude-code-plugin | `terraform@claude-plugins-official` | yes | project | — | verified-third-party |
| `laravel-boost` | claude-code-plugin | `laravel-boost@claude-plugins-official` | yes | project | — | verified-third-party |
| `ponytail` | claude-code-plugin | `ponytail@ponytail` | yes | user | — | community-third-party |
| `claude-mem` | claude-code-plugin | `claude-mem@thedotmack` | yes | user | — | community-third-party |
| `ui-ux-pro-max` | cdt-skill | *(local — none)* | yes | user | — | local-cdt-integration |

**Required** plugins (`doctor` fails if they're broken): `superpowers`, `code-review`, `frontend-design`,
`context7`. All others are optional — issues on them are warnings only.

### Security levels

| Level | Meaning |
|-------|---------|
| `official` | in `claude-plugins-official`, Anthropic-published — installs run immediately |
| `verified-third-party` | in `claude-plugins-official`, third-party authored — strict-gated |
| `community-third-party` | ships from an **independent marketplace**, not in the official catalog — strict-gated for manual installs, acquired by the [bootstrap](#all-in-one-install) |
| `local-cdt-integration` | a CDT-local skill — nothing to install |

Only `official` bypasses strict mode. Everything else prints its `claude plugin …` command instead of
running it (see [Install, enable & sync](#install-enable--sync)).

### Community plugins

Two community rows are registered so CDT can **detect, health-check and route around** them, and are
acquired by the bootstrap on first launch.

**These are installed for you.** Since 1.62.0 the SessionStart bootstrap adds their marketplaces and
installs them on first launch, **without prompting** — see [All-in-one install](#all-in-one-install). The
manual path below still applies if you turn the bootstrap off.

**Marketplace prerequisite.** Unlike every official row, these live on their own marketplaces, which are
**not** configured by default. Until you add one, `cdt-plugins install <id>` cannot resolve — the health
table says so and prints the exact command:

```
⨯ ponytail   claude-code-plugin   marketplace not configured: ponytail (add: claude plugin marketplace add DietrichGebert/ponytail)
```

```bash
claude plugin marketplace add DietrichGebert/ponytail   # then: cdt-plugins install ponytail
claude plugin marketplace add thedotmack/claude-mem     # then: cdt-plugins install claude-mem
```

`cdt-plugins sync` emits the same `marketplace add` line as a prerequisite above the install. CDT **never
runs it for you**, even with `CDT_PLUGIN_AUTO_INSTALL=1` — adding a marketplace is a trust decision that
stays with you. The slug comes from each row's optional `marketplaceSource` field.

The two plugins:

- **`ponytail`** ([DietrichGebert/ponytail](https://github.com/DietrichGebert/ponytail)) — injects a
  "laziest solution that works" ruleset (YAGNI → stdlib → native → one line) on every prompt and into every
  subagent, via its own `SessionStart` / `SubagentStart` / `UserPromptSubmit` hooks. Needs `node` on the
  **non-interactive** shell PATH. Level is set per session with `/ponytail lite|full|ultra|off`, or globally
  with `PONYTAIL_DEFAULT_MODE`; `PONYTAIL_SUBAGENT_MATCHER` (a case-insensitive regex on `agent_type`)
  scopes which subagents it reaches.
- **`claude-mem`** ([thedotmack/claude-mem](https://github.com/thedotmack/claude-mem)) — captures tool-use
  observations, compresses them with the Claude Agent SDK, and injects prior-session context back in. Runs a
  local Bun **worker service** (HTTP API + web viewer) over SQLite + Chroma, and auto-installs `bun` and
  `uv` on first start — hence `fallbackBehavior: warn-external-setup`. Settings live in
  `~/.claude-mem/settings.json` (`CLAUDE_MEM_MODEL`, mode/language), credentials in `~/.claude-mem/.env`
  (mode `0600`). Its observer agent runs tool-less by construction (`tools: []` + deny-list +
  `permissionMode: dontAsk` + `canUseTool` backstop + cwd jail), so it cannot edit your tree.

**Cost note (`claude-mem`).** Its `PostToolUse` hook fires on **every** tool call and each observation is
an SDK completion. On a subscription plan that spend lands on your own usage budget — set
`CLAUDE_MEM_MODEL` to a cheap model, or point `ANTHROPIC_API_KEY` / `ANTHROPIC_BASE_URL` in
`~/.claude-mem/.env` at a separate backend to keep it off your session quota. Watch it with `/cdt:budget`.

Detection joins this registry with Claude Code's own state files, all read-only and fail-open:

- installed plugins ← `~/.claude/plugins/installed_plugins.json` (matched by install identifier)
- enabled plugins ← `~/.claude/settings.json` → `enabledPlugins`
- known marketplaces ← `~/.claude/plugins/known_marketplaces.json`
- CLI dependencies ← probed on `PATH` (e.g. `typescript-language-server`, `intelephense`, `sourcekit-lsp`,
  `terraform`, `php`, `composer`, `node`)

### Where the registry lives

`cdt-plugins` and the router resolve the registry in this order:

1. `$CDT_PLUGIN_REGISTRY` (explicit override), else
2. a user copy at `~/.claude/.cdt/plugins-registry.json`, else
3. the shipped `config/plugins.json`.

The shipped file is read-only defaults. **Per-plugin user overrides live separately** in
`~/.claude/.cdt/plugins-state.json` and survive plugin updates (see [Per-plugin state](#per-plugin-state)).

---

## The `cdt-plugins` CLI

```
cdt-plugins — inspect & manage the CDT companion plugins (registry-driven; detection is read-only).

  list | status [--json]   health table: registry ⨝ installed ⨝ enabled ⨝ deps ⨝ overlay
  doctor [--json]          same table; exits non-zero only if a REQUIRED plugin / core dep is broken
  explain <id>             type, routing rules, deps, auth, security & fallback for one plugin
  sync                     print `claude plugin install/enable …` for missing enabled plugins
  enable  <id>             overlay=enabled  + claude plugin enable
  disable <id>             overlay=disabled + claude plugin disable
  install <id>             claude plugin install  (third-party gated by CDT_PLUGIN_STRICT, default on)
  update  <id>             claude plugin update
```

Run it directly or as the namespaced command:

```
~/.claude/bin/cdt-plugins list
/cdt:plugins doctor
```

**Read verbs** — `list` / `status` / `doctor` / `explain` / `sync` — are idempotent and never mutate
Claude Code state. **Write verbs** — `enable` / `disable` / `install` / `update` — shell out to the real
`claude plugin` CLI. There is **no `uninstall`**.

`--json` is available on the read verbs `list`, `status`, and `doctor` (it emits a flat `{id: status}`
object).

### The health table

`list` / `status` render one line per plugin: a status glyph, the id, its type, and a note.

| Glyph | Status | Meaning |
|:-----:|--------|---------|
| `✓` | `healthy` / `local` | installed + enabled (or a local CDT skill — always available) |
| `!` | `needs-auth` | enabled but needs a connection — `connect: /mcp` |
| `!` | `needs-setup` | enabled but an external binary/browser must be installed |
| `○` | `available` | in the registry, not installed — `install: cdt-plugins install <id>` |
| `○` | `disabled` | installed but disabled — `enable: cdt-plugins enable <id>` |
| `⨯` | `missing-dep` | a required CLI is off `PATH`, or the marketplace isn't configured |

The header summarizes counts: `cdt-plugins — N registered · N installed · N enabled`.

### `explain <id>`

Describes one plugin end-to-end: type, marketplace + scope, install id, default-on flag, what routes to it
(keywords / repo signals) and **whether those signals fire in the current directory**, CLI + binary
dependencies, auth requirement, security level, required flag, fallback behavior, and its current state
(`installed` / `enabled` / `overlay`). Unknown ids return a non-zero exit and point you at `list`.

---

## Health check (`doctor`)

`cdt-plugins doctor` prints the same table plus a broken-required count, and is designed for CI / scripts:

- It exits **non-zero (2)** only when a **required** plugin is `available` / `missing-dep` / `disabled`, or
  when the core dependency `python3` is missing.
- Non-required issues (a missing LSP binary, an unconnected `github`, etc.) are **warnings** and keep the
  exit code at 0.

Machine-readable form:

```
cdt-plugins doctor --json
# → {"superpowers": "healthy", "context7": "healthy", "typescript-lsp": "available", ...}
```

Missing `python3` is reported explicitly (`⨯ python3 missing (core dependency) — run: cdt-deps --install`),
since the whole subsystem depends on the standard-library `python3` helpers.

---

## Per-plugin state

Each plugin has an **effective state**: an explicit user overlay if set, otherwise the registry default
(`enabledByDefault: true → auto`, `false → disabled`). Overlays persist in:

```
~/.claude/.cdt/plugins-state.json
```

Valid overlay values: `enabled` · `disabled` · `manual` · `auto`. The file is written **atomically**
(temp file + `os.replace`), backed up to `.bak` before each change, and `chmod 600` inside a `chmod 700`
`~/.claude/.cdt/` jail. Because it is separate from the shipped registry, your choices **survive a plugin
update** that overwrites `config/plugins.json`.

- `cdt-plugins enable <id>` writes overlay `enabled`, then runs `claude plugin enable`.
- `cdt-plugins disable <id>` writes overlay `disabled`, then runs `claude plugin disable`.
- The advisory router **never recommends a plugin whose overlay is disabled**.

For a local CDT skill (`ui-ux-pro-max`), enable/disable update the overlay only — there is no Claude Code
plugin to toggle.

---

## Advisory routing

`cdt-plugin-route "<task>" [--json]` recommends plugins/skills for a task. It is **transparent GUIDANCE
that never blocks** and is fully fail-open — the orchestrator still decides. CDT stays authoritative:

```text
CDT orchestrator → task classification → CDT specialist → plugin/skill (advisory) → validation → cdt-verify
```

It unions repo signals (from `plib_detect_signals` plus a shallow top-level scan of `$PWD`) with task
keywords, then matches the registry's `activationRules`. Each recommendation carries a **one-line reason**.

### Routing rules

| Recommends | Repo signals | Task keywords | Notes |
|------------|--------------|---------------|-------|
| `frontend-design` | `package.json` (react/vite) | ui, css, component, design, layout, tailwind | pulls in `typescript-lsp` when TypeScript is present |
| `typescript-lsp` | `tsconfig.json`, `*.ts`/`*.tsx` | typescript, type error, ts | only alongside `frontend-design` |
| `laravel-boost` | `artisan`, `composer.json` | laravel, artisan, eloquent, blade | pulls in `php-lsp` when PHP is present |
| `php-lsp` | `composer.json`, `*.php` | php, intelephense, psr | only alongside `laravel-boost` |
| `terraform` | `*.tf`, `*.tfvars` | terraform, infra, iac, provision | |
| `swift-lsp` | `Package.swift`, `*.swift`, `*.xcodeproj` | swift, ios, xcode, swiftui | |
| `sentry` | `**/sentry.*`, `**/.sentryclirc` | sentry, crash, stacktrace, exception, error tracking | needs auth |
| `github` | `.github/**` | pull request, pr, issue, github, gh | needs auth |
| `context7` | — | docs, api, library, version, latest, sdk, migration | |
| `playwright` | `playwright.config.*`, `e2e/**`, `tests/e2e/**` | e2e, browser, screenshot, playwright, end-to-end | browsers not auto-installed |
| `code-review` | — | review, pr, diff, audit | **always defers** to CDT's code-reviewer |
| `ponytail` | — | simplify, refactor, over-engineering, yagni, minimal, boilerplate, cleanup | **always defers** to CDT's simplify step |
| `claude-mem` | — | memory, recall, previous session, last time, prior context, session history | **always defers** to the CDT vault |
| `superpowers` | — | (mode-gated) | see [Superpowers modes](#superpowers-modes) |

`ui-ux-pro-max` is registry-tracked and always available as a local skill, but the router does not emit a
recommendation for it — UI work routes to `frontend-design`.

### Conflicts — CDT always wins

A registry `conflicts` entry means the plugin overlaps a CDT-owned lane, so CDT wins and the plugin is
**deferred** (printed as `· <id> — deferred; CDT owns this (…)`):

- `code-review` conflicts with `cdt-code-reviewer`.
- `superpowers` conflicts with `cdt-planning`, `cdt-review`, `cdt-tdd`.
- `ponytail` conflicts with `cdt-simplify` — the completion mandate owns the simplify step, so the router
  never recommends ponytail on a refactor. (Its own hooks still inject the ruleset when you install it;
  the conflict only stops CDT from *routing* work to it.)
- `claude-mem` conflicts with `cdt-vault` — `cdt-recall` / `cdt-learn` stay the authoritative memory for
  orchestration decisions. Running both is fine; they are separate stores and CDT does not read
  claude-mem's.

### Superpowers modes

Set with `cdt-config superpowers-mode <mode>`:

| Mode | Behavior |
|------|----------|
| `off` | never suggest Superpowers |
| `manual` | user-invoked only — no automatic suggestion |
| `selective` (default) | suggest only on **high-complexity/risk** tasks (auth, payments, infra, migrations, refactor, architecture, debugging, performance, …) |
| `always` | always suggest (advisory) |

In every mode, Superpowers is suppressed for CDT-owned work (planning/roadmap, review/audit, TDD/tests) —
CDT keeps its own plan/review/TDD.

### `--json`

```
cdt-plugin-route "add an e2e browser test" --json
```

emits `{ precedence, superpowersMode, recommendations[], deferred[] }`, where each recommendation is
`{id, reason, advisory}` and each deferred entry is `{id, conflictsWith, note}`.

---

## Configuration

All settings persist in `~/.claude/claude-dev-team.env`; set them via `cdt-config`.

| Env var | Default | `cdt-config` subcommand | Meaning |
|---------|:-------:|-------------------------|---------|
| `CDT_PLUGINS_ENABLED` | `1` | `plugins-enabled on\|off` | master switch for detection / health / routing |
| `CDT_PLUGIN_AUTO_INSTALL` | `0` | `plugin-auto-install on\|off` | let `sync` actually run installs (opt-in) |
| `CDT_PLUGIN_AUTO_UPDATE` | `0` | `plugin-auto-update on\|off` | plugin updates stay user-gated |
| `CDT_PLUGIN_AUTO_ROUTE` | `1` | `plugin-auto-route on\|off` | advisory routing hints (never blocks) |
| `CDT_PLUGIN_SCOPE` | *(per-plugin)* | `plugin-scope user\|project` | overrides the scope passed to `claude plugin … -s <scope>`; **unset ⇒ each plugin's own registry scope** (not a uniform `project`) |
| `CDT_SUPERPOWERS_MODE` | `selective` | `superpowers-mode off\|manual\|selective\|always` | Superpowers gate |
| `CDT_PLUGIN_STRICT` | `1` | `plugin-strict on\|off` | gate auto-install of non-official plugins |
| `CDT_BOOTSTRAP_COMMUNITY` | `1` | `bootstrap-community on\|off` | SessionStart auto-adds the community marketplaces and installs ponytail + claude-mem, **without prompting** |
| `CDT_BOOTSTRAP_TIMEOUT` | `180` | *(env only)* | per-shell-out cap, in seconds, for the bootstrap |

```
~/.claude/bin/cdt-config plugins-enabled off        # turn the whole subsystem off
~/.claude/bin/cdt-config plugin-strict on           # keep third-party installs gated (default)
~/.claude/bin/cdt-config superpowers-mode selective # default
~/.claude/bin/cdt-config                             # show current config (plugin rows included)
```

> Note: `cdt-config reset` restores the **core** CDT defaults (enabled, effort, model, autonomy, engines).
> It does **not** touch the plugin env vars — reset those individually with the subcommands above.

---

## Install, enable & sync

### `install` / `update`

`cdt-plugins install <id>` and `update <id>` validate `<id>` against the registry and validate the install
identifier against a strict grammar before shelling out to `claude plugin <verb> <identifier> -s <scope>`.

- **Official** plugins run immediately.
- **Non-official** (`verified-third-party`: `github`, `sentry`, `terraform`, `laravel-boost`) are **gated
  by strict mode** (default on): the exact command is printed, **not executed**, with a one-time override:

  ```
  CDT_PLUGIN_STRICT=0 cdt-plugins install github
  ```
- A local skill (`ui-ux-pro-max`) has nothing to install.
- After installing a needs-auth plugin, you get a `/mcp` hint — CDT never authenticates for you.

### `sync`

`cdt-plugins sync` prints the exact `claude plugin install/enable … -s <scope>` commands for any plugin
whose desired state is active (`enabled` / `auto`) but that is missing or disabled. It is **advisory by
default** — it only *runs* those commands when **both** `CDT_PLUGIN_AUTO_INSTALL=1` **and**
`CDT_PLUGIN_STRICT=0`:

```
CDT_PLUGIN_AUTO_INSTALL=1 CDT_PLUGIN_STRICT=0 cdt-plugins sync
```

When everything is present it's a no-op (`✓ all enabled plugins present — nothing to sync.`).

### Zero-config companions

You rarely need `install` for the core four. The plugin manifest
([`.claude-plugin/plugin.json`](../.claude-plugin/plugin.json)) declares `superpowers`, `code-review`,
`frontend-design`, and `context7` as **dependencies**, so they auto-install (and, on Claude Code
≥ 2.1.143, auto-enable). The `sequential-thinking` MCP auto-registers via the shipped `.mcp.json`. See the
README [Requirements](../README.md#requirements).

---

## Authentication (github / sentry)

`github` and `sentry` are `needsAuth: true`. CDT **never auto-authenticates**:

- The health table shows them as `! needs-auth` once installed + enabled.
- `explain <id>` prints `needs auth : yes → connect with /mcp`.
- After `install`, you get a `connect it with /mcp` hint.

Connect them yourself from a Claude Code session with `/mcp`. Because both are `verified-third-party`, their
`install` is also strict-gated (run manually or with a one-time `CDT_PLUGIN_STRICT=0`).

---

## Security implications

- **Third-party plugins never auto-execute.** `plugin-strict` (default on) prints — but does not run — any
  non-`official` `claude plugin` command.
- **No `curl | sh`, no `eval`.** Every write shells out to the versioned `claude plugin` CLI with escaped
  arguments. Install identifiers must match `^[A-Za-z0-9._-]+@[A-Za-z0-9._-]+$` or the command is refused.
- **Captured CLI output is redacted.** All shelled-out output passes through a redactor that masks GitHub
  tokens/PATs, `sk-` keys, Slack `xox…` tokens, bearer tokens, JWTs, and `token/secret/password/api_key`
  assignments before it reaches your terminal.
- **No destructive removal.** There is no `uninstall` verb.
- **External toolchains are not auto-provisioned** — they warn and emit exact remediation instead:
  - LSP binaries: `typescript-language-server`, `intelephense`, `sourcekit-lsp`
  - the `terraform` CLI
  - Playwright browsers (`npx playwright install`)
  - `github` / `sentry` auth (`/mcp`)
- **State writes are jailed** to `~/.claude/.cdt/` (atomic, `chmod 600`, `chmod 700` dir), and the
  detection library performs **no network I/O** and is fail-open — a missing or corrupt file yields an
  empty result, never a crash.

---

## Troubleshooting

| Symptom | Likely cause | Fix |
|---------|--------------|-----|
| `no plugins resolved — registry unreadable?` | `config/plugins.json` missing/unparsable, or `python3` absent | run `cdt-deps --install`; confirm the registry path in the message |
| A required plugin shows `○ available` | companion not installed yet | `cdt-plugins install <id>`, or open a fresh session so manifest dependencies install |
| Plugin shows `○ disabled` | installed but disabled in `settings.json` / overlay | `cdt-plugins enable <id>` |
| `⨯ missing-dep — missing CLI: …` | an LSP/tool binary is off `PATH` | install the binary shown (e.g. `npm i -g typescript-language-server`) |
| `⨯ missing-dep — marketplace not configured` | `claude-plugins-official` not registered | `claude plugin marketplace add anthropics/claude-plugins-official` |
| `⨯ missing-dep — marketplace not configured: ponytail` / `: thedotmack` | a **community** row's own marketplace isn't added | run the `claude plugin marketplace add …` shown in the note, then `cdt-plugins install <id>` |
| `! needs-auth` | `github` / `sentry` installed but not connected | connect with `/mcp` |
| `! needs-setup` | Playwright/Laravel external setup pending | run the setup shown (e.g. `npx playwright install`) |
| `install` prints but doesn't run | third-party + strict mode | `CDT_PLUGIN_STRICT=0 cdt-plugins install <id>`, or run the printed command yourself |
| `cannot find plugins-lib.sh` | `~/.claude/bin` not yet populated | open a fresh Claude Code session to reinstall the CLIs |
| Router prints nothing | subsystem or routing disabled | check `cdt-config` (`plugins-enabled`, `plugin-auto-route`); it's also silent with no matches |

---

## Rollback

- **Turn the subsystem off:** `cdt-config plugins-enabled off` (detection/health/routing go silent).
- **Disable one plugin:** `cdt-plugins disable <id>` (overlay `disabled`; never recommended again).
- **Revert a setting to its default:** re-run the `cdt-config` subcommand (e.g. `cdt-config plugin-strict
  on`), or remove its line from `~/.claude/claude-dev-team.env` — defaults apply whenever a var is unset.
- **Reset overrides:** delete `~/.claude/.cdt/plugins-state.json` (a `.bak` is kept beside each write) to
  fall back to registry defaults.
- **Revert a customized registry:** remove `~/.claude/.cdt/plugins-registry.json` (or `git checkout
  config/plugins.json`) to return to the shipped defaults.

Plugins you actually installed via Claude Code remain installed — CDT has no `uninstall`. Remove them with
the Claude Code plugin UI / `claude plugin` CLI if you want them gone.

---

## See also

- README: [Plugin bootstrap & routing](../README.md#plugin-bootstrap--routing)
- [Architecture deep-dive](architecture.md)
- Command: [`/cdt:plugins`](../commands/plugins.md)
- [CHANGELOG](../CHANGELOG.md) — `[1.59.0]`, `[1.61.0]`, `[1.61.1]`
