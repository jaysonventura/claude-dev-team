# Mobile QA — Appium + UiAutomator2 (Android)

One harness, many apps. The shared flows in `flows/` contain zero app-specific
strings; each app supplies its own test ids through `apps/<id>.ts`.

## Install

```bash
npm install
npm run appium:drivers          # installs the uiautomator2 driver
cp .env.qa.example .env.qa      # then fill in QA_USERNAME / QA_PASSWORD
```

Requires Node >= 20.12, a JDK, the Android SDK (`ANDROID_HOME`, `adb` on PATH),
and a booted emulator or attached device (`adb devices -l`).

## Run

```bash
npm run test:e2e                # APP defaults to example-rn
APP=example-capacitor npm run test:e2e
npm run typecheck
```

Screenshots and the logcat window from failed tests land in
`$CDT_MQA_ARTIFACTS`, defaulting to `.claude/mobile-qa/<runid>/`.

## Add an app

1. Copy `apps/example-rn.ts` to `apps/<your-id>.ts`; set `id`, `kind`,
   `appPackage`, `appActivity`, and every entry in `selectors`.
2. Register it in `apps/index.ts` (one line).
3. `APP=<your-id> npm run test:e2e`.

`kind` decides how a test id becomes a selector: `react-native` → Android
`resource-id` (RN's `testID`), `native` → accessibility id (`content-desc`, i.e.
RN's `accessibilityLabel`), `capacitor` → a DOM `data-testid` driven inside the
webview. That mapping lives only in `support/selectors.ts`.

## Add a flow

Add a file under `flows/`, take `AppConfig` as the first argument, wrap the body
in `withUi(app, ...)` so Capacitor apps run in the webview, and reach elements
via `sel(app, '<logicalName>')`. New logical names go in the `SelectorName`
union in `apps/types.ts` — every app config then fails to compile until it maps
them, which is deliberate.

## House rules

- Accessibility id / `resource-id` / visible text only. No XPath: it breaks on
  every layout change.
- Wait on conditions (`waitForDisplayed`, `expect(...)`), never `pause(N)`.
- Retries are configured once, in `wdio.conf.ts` (`specFileRetries`).
- Credentials come from `.env.qa` (gitignored) and nowhere else.
- TypeScript is pinned to 5.9.x — WDIO 9's shipped types are built against it.
