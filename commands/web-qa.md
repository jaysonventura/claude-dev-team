---
description: Autonomous web QA — drive a real browser like a QA engineer (navigate, run full user journeys, assert the accessibility tree, catch JS errors and failed network calls, capture traces/video on failure, explain root causes, and generate or re-run Playwright E2E tests until green).
allowed-tools: Bash, Read, Write, Edit, Grep, Glob, Task
---

Apply the **`web-qa`** skill (with **`qa-shared`** for the loop, evidence and safety rules) and run the
autonomous QA loop for: $ARGUMENTS

Start with the preflight — never assume a browser is installed:

```
~/.claude/bin/cdt-web-qa doctor
```

Subcommands: `doctor` · `browsers [--install]` · `artifacts` · `scaffold` · `test` · `trace`.

Control-plane precedence: **Playwright MCP** (`mcp__playwright__browser_*` — already installed as a CDT
plugin dependency, no setup needed) for live driving, then `cdt-web-qa`, then raw `npx playwright`.

Rules that are not negotiable:

- **Validate the DOM and the accessibility tree, never an image.** `browser_snapshot` is the source of
  truth; screenshots are evidence for humans, not assertions. No pixel or visual-diff checks.
- **Locators in priority order:** `getByRole()` → `getByLabel()` → `getByText()` → `data-testid`.
  XPath and coordinate clicks are a documented last resort only.
- **Console and network are first-class.** A page that looks right but logged a JS error or a failed/5xx
  request is a **FAIL**, not a pass — check `browser_console_messages` and `browser_network_requests`
  every scenario.
- **Verify backend truth, not just rendered text** — an optimistic UI that never persisted is the classic
  false pass.
- Credentials from env only; payment flows **sandbox only**; artifacts stay gitignored; never point a
  destructive suite at production.
- **Never report a pass you did not observe.** If no browser is installed, say so and stop.

If the app repo has no harness, offer `cdt-web-qa scaffold` to drop in the shared Playwright framework
(cross-browser projects, per-app config under `apps/`), then add the app's config.

Report per `qa-shared`: scenario table, artifact paths, ranked root cause for each failure, and end every
fixed bug as a **durable Playwright spec** — not a screenshot.
