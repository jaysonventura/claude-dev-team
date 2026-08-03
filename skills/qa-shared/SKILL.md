---
name: qa-shared
description: The QA contract shared by web and mobile autonomous testing — the verify loop, artifact conventions, failure-analysis format, and credential/payment safety rules. Auto-applies alongside web-qa or mobile-qa; read it before running any E2E scenario, writing a QA report, or explaining a test failure, so a browser run and a device run are held to the same standard.
---

# QA — the shared contract

One QA engineer, two surfaces. `web-qa` drives a browser, `mobile-qa` drives a device; **the loop,
the evidence rules, the artifact layout, the report format and the safety rules below are identical
for both.** Platform skills own only what is genuinely platform-specific (selectors, control plane).

## The autonomous loop (both surfaces)

```
doctor → build/deploy → launch → read the accessibility tree → act → assert
   └── FAIL → capture evidence → rank root cause → fix or file → re-run via cdt-verify → repeat
```

1. **Preflight.** `cdt-web-qa doctor` / `cdt-mobile-qa doctor`. Any **FAIL** → fix or report BLOCKER.
   Never run scenarios on a red preflight; every downstream failure is noise.
2. **Automation-first.** Build/serve/deploy the app under test through the repo's own automation —
   Makefile target first, then package scripts, `scripts/`, docs/CI. Never improvise. A Makefile target
   that fails → **STOP and report**. (skill: `automation-first`)
3. **Fresh state per scenario.** Mobile: `reset <pkg>`. Web: a fresh browser context (new storage state).
   Shared state between scenarios is the #1 source of phantom failures.
4. **Derive selectors, never invent them.** Read the real accessibility tree first — `browser_snapshot`
   (web) or `ui --json` (mobile). A selector taken from source is a guess; one from the tree is a fact.
5. **Execute + assert** per the platform's `references/scenarios.md`.
6. **On failure, capture before you reason.** Then state a ranked root cause (below).
7. **Fix or file, then re-run the same command through `cdt-verify -- <cmd>`.** Only a `cdt-verify`
   exit code is evidence. Evidence recorded *before* your last edit is stale and does not count.
8. **Bounded.** Same command + same failure signature twice → **stuck loop**: escalate to the
   **Bug Council** (`/cdt:bug-council`); do not attempt a third identical patch. Hard cap
   `CDT_MAX_ITERATIONS` (default 5). Hitting it is **not** permission to claim success — report
   `DEFERRED`/`BLOCKER` with what is still red.

This is `skills/orchestration/SKILL.md` STEP 3b applied to a UI. Same vocabulary, same gate.

## Two layers — both required, on both surfaces

| Layer | Web | Mobile | Lifetime |
|-------|-----|--------|----------|
| **Exploratory** — reproduce, poke, explore | Playwright MCP | mobile MCP / `cdt-mobile-qa` | this session |
| **Regression** — prove it stays fixed | Playwright spec in `qa-web/` | Appium spec in `qa/` | forever |

**Every confirmed bug ends as a durable test, not a screenshot.** A screenshot proves it broke once; a
committed spec proves it stops breaking. Exploration finds the bug; the harness is the deliverable.

## Artifacts — one layout for both

```
<repo>/.claude/qa/<platform>/<runid>/      platform = web | mobile
```
Override with `CDT_QA_ARTIFACTS`. The artifacts root **ignores itself** (a `.gitignore` containing `*`
is written when the directory is created), because captures carry session tokens, OTPs and PII.
Every capture prints its absolute path on stdout so an agent can cite it.

## Failure analysis — the required format (both surfaces)

"The login test failed" is not a report. Every failure carries:

| Field | Content |
|-------|---------|
| **Where** | the exact selector or assertion that failed, and the step number |
| **State** | the accessibility tree / DOM snapshot **at the moment of failure**, not a later one |
| **Logs** | browser console + failed network requests (web) · `logcat` window (mobile) |
| **Cause** | ranked: **app bug** / **test bug** / **env or flake** — with the evidence for the top pick |
| **Artifacts** | screenshot, video, and (web) trace paths |

**Flake triage:** re-run the failing step **once**. Passing on retry is a **flake finding**, not a pass —
report it as flaky with the suspected timing cause. "It passed the second time" never closes a ticket.

Apply `root-cause-analysis`. For genuinely hard diagnosis, convene the Bug Council rather than guessing.

## Reporting

Per `skills/orchestration/SKILL.md`: a gate table (scenario → pass/fail) with fenced output for
failures, artifact paths, tests added, and a `BLOCKER` for anything unverified. If a scenario could not
run (no device, no browser, no sandbox creds, no build), **say exactly that** — never a soft "looks fine".

## Security & safety (non-negotiable, identical on both surfaces)

| Rule | Why |
|------|-----|
| **Never hardcode credentials** in a test, config or spec. Read from env / a gitignored `.env.qa`. | A committed test password is a committed password. |
| **Never run payment flows against production or a live processor.** Sandbox / test-mode keys only. | Real money, real chargebacks. |
| **Only production payment creds available → refuse and report.** Do not "just test carefully". | There is no careful version of charging a real card. |
| **Never commit artifacts** — screenshots, video, traces, logs. The artifacts root must be gitignored. | They contain PII, session tokens and OTPs. |
| **Video and traces are captured automatically on failure** — a failed login or payment test therefore records the credential or card entry by default. | This makes the never-paste-artifacts rule more load-bearing, not less. |
| **Scrub tokens** before pasting any log into a report or PR. | Console logs and logcat leak `Authorization:` headers and refresh tokens routinely. |
| **Never point a destructive suite at production.** Confirm the target URL / device before CRUD or payment scenarios. | A QA delete against prod data is unrecoverable. |

Check the app repo's `.gitignore` covers the artifacts root and `.env.qa` **before** the first run.
