---
name: web-qa
description: Use for any web QA or browser end-to-end testing work — "test this web app", drive a site to reproduce a bug, write or fix Playwright E2E specs, chase a flaky web test, check a flow in Chromium/Firefox/WebKit, verify a form/login/checkout in a real browser, or investigate a console error or failed XHR behind a broken page. Runs the autonomous QA loop against a live browser (preflight → serve → read the accessibility snapshot → act → assert UI + console + network + backend → capture evidence and root cause on failure → re-verify through cdt-verify) and turns every confirmed bug into a durable Playwright spec.
---

# Web QA — autonomous browser-driven testing

Drive a real browser, find real bugs, prove the fix. **Never claim a pass you did not observe.** No
reachable app URL → say so and stop; a QA report with no browser behind it is a fabrication.

**The loop, artifacts, failure format, reporting and every credential/payment/PII rule live in
`skills/qa-shared/SKILL.md`. Read it first. This file is only what is web-specific.**

## Control plane — precedence (use the first that covers it)

| # | Layer | Use for | Never |
|---|-------|---------|-------|
| 1 | **Playwright MCP** (`mcp__playwright__browser_*`) | Live exploratory driving — navigate, snapshot, click, fill, read console + network, resize, tabs | — |
| 2 | **`cdt-web-qa`** (`~/.claude/bin/cdt-web-qa`) | Lifecycle: preflight, browser engines, artifacts, harness scaffold, running the suite, opening traces | — |
| 3 | **raw `npx playwright`** | Only what neither above wraps — **say so explicitly when you drop to it** | Hand-writing a command `cdt-web-qa` already wraps |

The MCP **needs no install step** — it ships as a CDT plugin dependency and is already registered. There
is no `claude mcp add` to run and no version to pin here.

| MCP tool | Use |
|----------|-----|
| `browser_navigate` · `browser_navigate_back` | go to a URL / back |
| **`browser_snapshot`** | **the primary observation** — accessibility tree + element refs |
| `browser_click` · `browser_type` · `browser_fill_form` · `browser_select_option` · `browser_press_key` · `browser_hover` | act (refs come from the snapshot) |
| `browser_console_messages` · `browser_network_requests` | the two signals below — check on **every** scenario |
| `browser_wait_for` | wait on text/state — never a sleep |
| `browser_resize` · `browser_tabs` | responsive viewports / multi-tab session tests |
| `browser_file_upload` · `browser_handle_dialog` | uploads, `confirm()`/`alert()` dialogs |
| `browser_evaluate` | read DOM/JS state an assertion needs (e.g. `scrollWidth`) |
| `browser_take_screenshot` | **evidence for humans only — never an assertion** |

## The frozen CLI (do not invent subcommands)

| Command | Purpose |
|---------|---------|
| `doctor` | node / playwright / browser-engine / MCP preflight → PASS·WARN·FAIL, exit 1 on FAIL |
| `browsers [--install]` | which engines are installed (chromium/firefox/webkit); install the missing ones |
| `artifacts [--dir] [--clean]` | the shared run dir (see `qa-shared`) |
| `scaffold [--dir <path>] [--force]` | copy the shipped Playwright harness into an app repo |
| `test [--app <id>] [--browser chromium\|firefox\|webkit] [-- <playwright args>]` | run the suite |
| `trace <file>` | open a Playwright trace |

Env: `CDT_QA_ARTIFACTS` (unified with mobile: `<repo>/.claude/qa/<platform>/<runid>`).

**Target safety is enforced, not advised.** Each app's `baseURL` comes from its own env var (see
`apps/<id>.ts` — e.g. `QA_EXAMPLE_APP_URL`); there is no global base-URL override. The harness **throws
at config load** if that URL is not loopback, unless `CDT_QA_ALLOW_REMOTE=1` is set. The suite deletes
records and exercises payment flows as an authenticated admin, so pointing it away from localhost has to
be a deliberate act. Never set `CDT_QA_ALLOW_REMOTE=1` against production.

## Observation contract — the snapshot is the truth, the screenshot is not

**`browser_snapshot` is the primary observation. Never validate by image recognition or pixel
comparison.** The accessibility snapshot is a structured, assertable fact: roles, names, states, values,
and the refs the action tools consume. A screenshot is a picture — you cannot assert on it without
guessing, and a "looks right" judgement from an image is exactly the fabricated pass this skill exists to
prevent.

| Question | Answer with | Never with |
|----------|-------------|------------|
| Is the control there / labelled / enabled? | `browser_snapshot` → `expect(locator).toBeVisible()` / `toBeEnabled()` | eyeballing a screenshot |
| Did the value change? | snapshot value → `toHaveValue()` / `toHaveText()` | a pixel diff |
| Did the layout break? | `browser_evaluate` → `scrollWidth > clientWidth`, control reachable + clickable | a visual-regression baseline |
| What did the user see when it failed? | screenshot + video + trace, attached as **evidence** | as the assertion |

Screenshots and video are captured for the human reading the report. They are never the reason a
scenario passed.

## Console + network are first-class signals — not optional extras

**Every scenario checks both.** A page that renders correctly while throwing a JS exception or eating a
500 is a **FAIL**, not a pass. This is the whole difference between web QA and clicking around.

| Signal | Live (MCP) | In the harness | Fails the scenario when |
|--------|-----------|----------------|-------------------------|
| JS errors | `browser_console_messages` | `page.on('pageerror', …)` + `page.on('console', m => m.type() === 'error')` | any uncaught exception, or a console `error` the app did not deliberately log |
| Failed requests | `browser_network_requests` | `page.on('requestfailed', r => r.failure())` + `page.on('response', r => r.status() >= 400)` | any 4xx/5xx or aborted request in the flow, including ones the UI swallows |

Wire both listeners in a fixture so **no spec can forget them**, and fail the test in `afterEach` if
either collected anything unexpected. An expected 4xx (a validation test that deliberately posts bad
input) gets an explicit allowlist entry in that spec — never a blanket exemption.

## Frontend state vs backend truth

A UI that renders optimistically and never persisted is the classic false pass. **Assert the effect, not
the render.**

1. Assert the UI (`toBeVisible`, `toHaveText`).
2. Assert the wire: `page.waitForResponse(r => r.url().includes('/api/orders') && r.ok())`, or read the
   captured `browser_network_requests` entry — status **and** payload.
3. Assert persistence: `page.reload()` (or a fresh context) and re-assert. An item that vanishes on
   reload never existed.
4. For anything the UI does not surface, verify server-side with the `request` fixture
   (`await request.get('/api/orders/123')`) — same session, real API.

Rule of thumb: **create/update/delete scenarios are not done until they survive a reload.**

## Cross-browser

| Situation | Run |
|-----------|-----|
| Iterating on a scenario, debugging, exploratory driving | `chromium` only |
| Before declaring a flow green · release gate · CI · any CSS/layout, date/time input, media, clipboard, or auth-redirect work | all three |
| A bug reported by a Safari/Firefox user | that engine **first**, then chromium to see if it is engine-specific |

Config is `projects` in `playwright.config.ts` using `devices['Desktop Chrome' | 'Desktop Firefox' |
'Desktop Safari']`; drive one with `cdt-web-qa test --browser webkit`.

**A webkit-only failure is a real finding, not flake.** WebKit is Safari — every iOS browser is WebKit.
Report it as a bug against the app with the engine named, and only downgrade it to a harness problem
after you have shown the *test* (not the app) is engine-dependent — e.g. `context.grantPermissions` for
clipboard is Chromium-only and errors during setup on the other two, which reads like an app bug and is
not one.

## Responsive

Resize with `browser_resize` live, or `test.use({ viewport: { width, height } })` / a device preset in a
project. Standard sweep: **375×667 (mobile) · 768×1024 (tablet) · 1280×720 (desktop)**.

Responsive checks assert **layout behaviour, never pixels**:

- Every interactive control in the flow is still reachable and clickable at that width (the nav collapsed
  into a hamburger still opens; the submit button is not off-screen).
- No horizontal overflow: `browser_evaluate` → `document.documentElement.scrollWidth <=
  document.documentElement.clientWidth`.
- Content that must stay visible is visible; content that must collapse actually collapsed.

Never a screenshot baseline. See the strict-mode trap in `references/scenarios.md` §9 — at mobile widths
the desktop *and* mobile navs are usually both in the DOM.

## Traces — the one artifact worth more than a screenshot

Set `trace: 'retain-on-failure'` in `playwright.config.ts` `use` (valid modes include `'off'`, `'on'`,
`'retain-on-failure'`, `'on-first-retry'`, `'on-all-retries'`, `'retain-on-first-failure'`). Pair with
`screenshot: 'only-on-failure'` and `video: 'retain-on-failure'`.

A trace carries what no screenshot can: every action with its **before/after DOM snapshot**, the full
console and network log, the source line for each step, and a time-travel scrubber. It is the difference
between "the click did nothing" and "the click hit an overlay that was still animating".

Open it: `cdt-web-qa trace <path>` (wraps `npx playwright show-trace`). Read the failing action's *before*
snapshot first — that is the state the selector actually saw.

## The harness (scaffolded, not hand-rolled)

`cdt-web-qa scaffold --dir <app-repo>/qa-web` drops a TypeScript Playwright harness — **a subdirectory,
never the repo root**; existing files are skipped, not overwritten, without `--force` (read the per-file
`wrote` / `skip (exists)` lines before assuming a template landed).

| Path | Contains |
|------|----------|
| `qa-web/apps/<app>.ts` | per-app config: base URL, creds source, selector map, feature flags |
| `qa-web/flows/` | shared flows (login, nav, CRUD) **parameterized by app config** |
| `qa-web/specs/` | per-app specs composed from flows |
| `playwright.config.ts` | `projects` for chromium/firefox/webkit, trace/video/screenshot on failure |

**Multi-app reuse:** one harness, N app configs. A new app is a new `qa-web/apps/<name>.ts` + its specs —
never a second harness. If a flow needs an `if (app === 'x')`, the difference belongs in the app config.

Authenticate once in a `setup` project that writes `storageState` to a **gitignored** auth file, and list
it in `dependencies` — never log in inside every spec. One auth file **per role** (see §2 in
`references/scenarios.md`).

## References

| File | Covers |
|------|--------|
| `references/scenarios.md` | 11 playbooks — steps, assertions, and the specific web trap that makes each one flaky |
| `references/selectors.md` | the locator priority order, strict mode, auto-waiting, and the XPath ban |
| `skills/qa-shared/SKILL.md` | **the loop, artifacts, failure-analysis format, reporting, credentials/payments/PII** |
