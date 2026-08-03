---
name: mobile-qa
description: Use for any mobile QA or Android end-to-end testing work — "test the app on a device/emulator", install/launch an APK, drive a real app to reproduce a bug, write or fix Appium / UiAutomator2 / WebdriverIO mobile tests, chase a flaky Android test, or QA a Capacitor/React Native build. Runs the autonomous QA loop (preflight → install → read the a11y tree → execute → assert → capture evidence + root cause on failure → re-verify through cdt-verify until green) and turns every confirmed bug into a durable regression test.
---

# Mobile QA — autonomous device-driven testing

Drive a real Android device/emulator, find real bugs, prove the fix. **Never claim a pass you did not
observe.** No device attached → say so and stop; a QA report with no device behind it is a fabrication.

## Control plane — precedence (use the first that covers it)

| # | Layer | Use for | Never |
|---|-------|---------|-------|
| 1 | **Mobile MCP tools** (if wired) | Live exploratory driving — tap/swipe/type/screenshot/read UI, model-native | — |
| 2 | **`cdt-mobile-qa`** (`~/.claude/bin/cdt-mobile-qa`) | Everything device-lifecycle: preflight, install, launch, reset, capture, logcat, net, perms, Appium | — |
| 3 | **raw `adb`** | Only what neither above wraps — **say so explicitly when you drop to it** | Hand-writing an `adb` command a subcommand already wraps |

This is the same hierarchy as `automation-first` — repo/tool automation beats improvised commands. Wire an
MCP once, then prefer it for interaction:

```bash
claude mcp add mobile -- npx -y @mobilenext/mobile-mcp@1.0.0
claude mcp add appium -- npx -y appium-mcp-server@0.1.61
```

**Pin the version — never `@latest`.** An MCP server gets arbitrary code execution in your session *and*
full control of the device. With `@latest`, `npx -y` re-resolves from the registry on every launch, so a
hijacked or compromised publish runs automatically the next time you start a session, with no diff to
review. Both are third-party (`appium-mcp-server` is pre-1.0); bump the pin deliberately, the way
`templates/package.json` pins every devDependency exactly.

## The frozen CLI (do not invent subcommands)

| Command | Purpose |
|---------|---------|
| `doctor` | adb/appium/uiautomator2-driver/node/device/MCP preflight → PASS·WARN·FAIL + fix hints |
| `devices` | adb devices + api level + model |
| `install <apk>` | `adb install -r -g` (`-r` replace, `-g` grant all runtime perms). For clean state use `reset <pkg>` |
| `launch <pkg> [activity]` / `stop <pkg>` | am start (waits for window) / force-stop |
| `reset <pkg>` | `pm clear` — **fresh state per scenario** |
| `shot [name]` / `record start\|stop [name]` | screencap / screenrecord mp4 → artifacts |
| `ui [--json]` | uiautomator dump → a11y tree (`resource-id`, `content-desc`) |
| `logcat [--since <ts>] [--pkg <pkg>] [--crash]` | scoped log window |
| `net on\|off` | data/wifi toggle for offline scenarios |
| `perm grant\|revoke <pkg> <perm...>` | runtime permissions |
| `artifacts [--dir] [--clean]` | artifact dir path / wipe |
| `appium start\|stop\|status` | Appium server lifecycle |
| `scaffold [--dir <path>] [--force]` | copy the shipped WDIO harness into an app repo |

Env: `CDT_MQA_DEVICE` (adb serial, required when >1 device), `CDT_MQA_ARTIFACTS` (default `.claude/mobile-qa/<runid>`).

## The autonomous QA loop

```
doctor → build/install → launch → ui → act → assert
   └── FAIL → shot + record + logcat + root cause → fix or file → re-run via cdt-verify → repeat
```

1. **Preflight.** `cdt-mobile-qa doctor`. Any **FAIL** → fix it or report BLOCKER. Do not proceed on a
   red preflight; every downstream failure will be noise.
2. **Build/install.** Check the app repo's automation *first* (`automation-first`): `make up-dev`,
   `package.json` scripts, `npx cap sync`, gradle wrapper — in that order. **Never improvise a build.**
   A Makefile target that fails → **STOP and report**, do not try another path.
3. **Fresh state.** `reset <pkg>` before every scenario. Shared state between scenarios is the #1 source
   of phantom failures.
4. **Derive, don't guess.** `ui --json` to read the actual a11y tree before writing a selector. A selector
   you invented from the source code is a guess; one from the dump is a fact. See `references/selectors.md`.
5. **Execute + assert** per the playbook in `references/scenarios.md`.
6. **On failure, capture before you think:** `shot`, `logcat --pkg <pkg> --since <t>`, the `ui` dump at the
   point of failure, and the video if one is recording. Then state a **ranked root cause** (below).
7. **Fix or file**, then **re-run the same command through `cdt-verify -- <cmd>`**. Only a `cdt-verify`
   exit code is evidence; evidence recorded before your last edit is stale.
8. **Bounded.** Same command + same signature failing twice → **stuck loop**: escalate to the **Bug
   Council** (`/cdt:bug-council`), do not attempt a third identical patch. Hard cap `CDT_MAX_ITERATIONS`
   (default 5) — hitting it is **not** permission to claim success; report `DEFERRED`/`BLOCKER` with what
   is still red.

This is `skills/orchestration/SKILL.md` STEP 3b applied to a device. Same vocabulary, same gate.

## Two layers — both are required

| Layer | Tool | Lives | Lifetime |
|-------|------|-------|----------|
| **Exploratory** — reproduce, poke, explore | MCP / `cdt-mobile-qa` | nowhere (artifacts only) | this session |
| **Regression** — prove it stays fixed | Appium + UiAutomator2 via the WDIO harness | `qa/` in the app repo | forever |

**Every confirmed bug ends as a durable test, not a screenshot.** A screenshot proves it broke once; a
committed spec proves it stops breaking. Exploratory driving is how you *find* the bug; the harness is the
deliverable.

## The harness (scaffolded, not hand-rolled)

`cdt-mobile-qa scaffold --dir <app-repo>/qa` drops a TypeScript Appium + UiAutomator2 + WebdriverIO harness
(**a subdirectory, never the repo root** — the harness owns `qa/`, and the CLI refuses a project root
because overwriting the app's `.gitignore` would un-ignore its real `.env`)
(existing files are **skipped, not overwritten**, without `--force` — read the per-file `wrote` /
`skip (exists)` lines before assuming a template landed). To onboard an app, follow the harness README:
copy `apps/example-rn.ts` (or `example-capacitor.ts`) to `apps/<your-id>.ts`, fill in `appPackage`,
`appActivity` and every `selectors` entry, then register it in `apps/index.ts`:

| Path | Contains |
|------|----------|
| `qa/apps/<app>.ts` | per-app config: package, activity, capabilities, base URL, test creds source |
| `qa/flows/` | shared flows (login, nav, CRUD) **parameterized by app config** |
| `qa/specs/` | per-app specs composed from flows |
| `sel(app,'name')` | the sanctioned way to reach an element — routes per app `kind` (RN → `resource-id`, native → accessibility id, Capacitor → DOM `data-testid`). Never call `by.*` directly in a flow |

**Multi-app reuse:** one harness, N app configs. A new app is a new `qa/apps/<name>.ts` + its specs — never
a second harness. If a flow needs an `if (app === 'x')`, the difference belongs in the app config.

Verified capability names (context7, uiautomator2-driver 8.2.2): `appium:automationName: 'uiautomator2'`
(the driver README's own wording is "Must be set to `'uiautomator2'`" — the value is case-insensitive at
runtime, so do **not** "correct" it to `UiAutomator2`; both work and the lowercase form is documented),
`appium:appPackage`, `appium:appActivity`, `appium:autoGrantPermissions` (needs targetSdk ≥ 23),
`appium:noReset`, `appium:fullReset`, `appium:enforceAppInstall`, `appium:autoWebview`,
`appium:printPageSourceOnFindFailure` (turn this on — it dumps the tree on every find failure).
Versions on npm today: `appium` 3.6.0, `appium-uiautomator2-driver` 8.2.2, `webdriverio` 9.30.1.

## Root-cause discipline

Apply `root-cause-analysis`. A failure report that says "login test failed" is not a report. Required:

| Field | Content |
|-------|---------|
| **Where** | the exact selector or assertion that failed, and the step number |
| **State** | the `ui` a11y tree at the moment of failure (not a later one) |
| **Logs** | `logcat --pkg <pkg> --since <step-start>` — the window around the failure, not the whole buffer |
| **Cause** | ranked: **app bug** / **test bug** / **env or flake** — with the evidence for the top pick |
| **Artifacts** | screenshot + video paths |

**Flake triage:** re-run the failing step **once**. Passing on retry is a **flake finding**, not a pass —
report it as flaky with the suspected timing cause (see the traps in `references/scenarios.md`). Never let
"it passed the second time" close a ticket.

## Security & safety (non-negotiable)

| Rule | Why |
|------|-----|
| **Never hardcode credentials** in a test/config/spec. Read from env or `.env.qa`, which is **gitignored**. | A committed test password is a committed password. |
| **Never run payment/transaction flows against production or a live payment processor.** Sandbox / test-mode credentials only. | Real money, real chargebacks. |
| **Only prod payment creds available → refuse and report.** Do not "just test carefully". | There is no careful version of charging a real card. |
| **Never commit artifacts** — screenshots, video, logcat. The artifacts dir must be gitignored. | They contain PII, session tokens, and OTPs. |
| **Video is captured AUTOMATICALLY on every failed test** — you do not opt in. A failed login or payment test therefore yields an mp4 **of the credential or card entry**, on disk, by default. | This makes the never-paste-artifacts rule more load-bearing, not less: a video leaks what a screenshot would have cropped. |
| **Scrub tokens** from logcat before pasting into any report or PR. | Logcat leaks `Authorization:` headers and refresh tokens routinely. |

Check the app repo's `.gitignore` covers `.claude/mobile-qa/` and `.env.qa` **before** the first run, not after.

## Reporting

Report per `skills/orchestration/SKILL.md`: gate table (scenario → pass/fail) with fenced output for
failures, artifact paths, tests added, and a `BLOCKER` for anything you could not verify. If a scenario
could not run (no device, no sandbox creds, no build), say **exactly that** — never a soft "looks fine".
