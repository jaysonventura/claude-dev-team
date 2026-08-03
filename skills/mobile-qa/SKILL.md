---
name: mobile-qa
description: Use for any mobile QA or Android end-to-end testing work — "test the app on a device/emulator", install/launch an APK, drive a real app to reproduce a bug, write or fix Appium / UiAutomator2 / WebdriverIO mobile tests, chase a flaky Android test, or QA a Capacitor/React Native build. Runs the autonomous QA loop (preflight → install → read the a11y tree → execute → assert → capture evidence + root cause on failure → re-verify through cdt-verify until green) and turns every confirmed bug into a durable regression test.
---

# Mobile QA — autonomous device-driven testing

Drive a real Android device/emulator, find real bugs, prove the fix. **Never claim a pass you did not
observe.** No device attached → say so and stop; a QA report with no device behind it is a fabrication.

> **Read `qa-shared` alongside this.** The autonomous loop, the `cdt-verify` gate, the artifact layout
> (`.claude/qa/mobile/<runid>`), the failure-analysis format, the report shape, and the credential /
> payment / PII rules are **shared with `web-qa`** and defined once there. This file covers only what is
> mobile-specific: the device control plane, the Android traps, and native/RN/Capacitor selectors.

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

Env: `CDT_MQA_DEVICE` (adb serial, required when >1 device), `CDT_QA_ARTIFACTS` (shared with `cdt-web-qa`;
default `.claude/qa/mobile/<runid>` — `CDT_MQA_ARTIFACTS` still honoured for back-compat).

## The autonomous QA loop

**Defined in `qa-shared`** — preflight → build/install → launch → read the a11y tree → act → assert →
capture + rank root cause on failure → re-run through `cdt-verify` until green, bounded by
`CDT_MAX_ITERATIONS`, escalating to the Bug Council on a repeated signature. Read it there; it is
identical for web and mobile. Only the device-specific steps differ:

| Step | Mobile specifics |
|------|------------------|
| Preflight | `cdt-mobile-qa doctor` — any FAIL means no device work runs |
| Build/install | check the app repo's Makefile / package scripts first (`automation-first`), then `install <apk>` |
| Fresh state | `reset <pkg>` (`pm clear`) before **every** scenario |
| Observe | `ui --json` — the a11y tree is the fact; a selector from source is a guess |
| Launch check | `launch` polls until the package is actually foregrounded, so a crash-on-start fails loudly |

## Two layers — both are required

**Defined in `qa-shared`.** Mobile mapping: exploratory driving is a mobile MCP or `cdt-mobile-qa`;
the durable layer is an Appium + UiAutomator2 spec in the app repo's `qa/`. Every confirmed bug ends
as a committed spec, not a screenshot.

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

## Root-cause discipline, reporting, and safety

**All three are defined in `qa-shared` and are identical for web and mobile** — the required failure
fields (where / state / logs / ranked cause / artifacts), flake triage, the report shape, and the
credential, sandbox-only-payment, artifact-PII and scrub rules. Do not restate them here; a rule
written twice is a rule that drifts.

Mobile-specific notes only:

| Topic | Mobile specifics |
|-------|------------------|
| Logs | `logcat --pkg <pkg> --since <step-start>` — the window around the failure, not the whole buffer |
| State at failure | the `ui` dump taken **at** the failing step, not a later one |
| Destructive ops | `reset` wipes app data and `net off` leaves the device offline — both hit a REAL device, possibly the user's own phone |
| Permissions | `install -g` auto-grants every runtime permission; use `reset` to get back to an ungranted state |

Artifacts land in `.claude/qa/mobile/<runid>` (`CDT_QA_ARTIFACTS`), alongside `.claude/qa/web/` —
one root, per `qa-shared`.
