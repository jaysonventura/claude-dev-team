---
description: Autonomous mobile QA — drive a real Android device/emulator like a QA engineer (install, run user scenarios end-to-end, capture screenshots/video/logcat on failure, explain root causes, and generate or re-run Appium E2E tests until green).
allowed-tools: Bash, Read, Write, Edit, Grep, Glob, Task
---

Apply the **`mobile-qa`** skill and run the autonomous QA loop for: $ARGUMENTS

Start with the device preflight — never assume a device is attached:

```
~/.claude/bin/cdt-mobile-qa doctor
```

Subcommands: `doctor` · `devices` · `install <apk>` · `launch <pkg>` · `stop` · `reset` · `shot` ·
`record start|stop` · `ui [--json]` · `logcat` · `net on|off` · `perm grant|revoke` · `artifacts` ·
`appium start|stop|status` · `scaffold`.

The loop (the skill holds the detail): **preflight → install/launch → read the a11y tree → run the
scenario → assert → on failure capture screenshot + video + logcat and name the root cause → fix →
re-run through `cdt-verify` until green**, bounded by `CDT_MAX_ITERATIONS`.

Control-plane precedence: a wired mobile **MCP** server first, then `cdt-mobile-qa`, and raw `adb` only
for what neither wraps. Before building or installing the app, check its **Makefile / package scripts** —
never improvise a build (`automation-first`).

Rules that are not negotiable: **stable selectors** (accessibility id / `resource-id` / `content-desc`;
XPath only as a documented last resort), credentials from env only, payment flows against **sandbox
only**, artifacts stay gitignored, and **never report a pass you did not observe** — if no device is
attached, say so and stop.

If no harness exists in the app repo, offer `cdt-mobile-qa scaffold` to drop in the shared
Appium + UiAutomator2 (WebdriverIO) framework, then add the app's config under `qa/apps/`.

Report each confirmed defect with its evidence paths, and end every fixed bug as a **durable E2E test** —
not just a screenshot.
