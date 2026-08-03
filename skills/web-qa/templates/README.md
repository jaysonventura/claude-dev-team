# Web QA — Playwright

One harness, many apps. The shared flows in `flows/` contain zero app-specific
strings; each app supplies its own selectors through `apps/<id>.ts`.

## Install

```bash
npm install
npm run browsers                # downloads chromium, firefox, webkit
cp .env.qa.example .env.qa      # then fill in the URLs and QA credentials
```

Requires Node >= 20.12. The app under test must already be serving on its
`baseURL` — start it with the app repo's own automation (`make up-dev`, etc.).

## Target safety

Each app reads its base URL from its own env var (see `apps/<id>.ts`). The harness **throws at config
load** unless that URL is loopback — this suite deletes records and runs payment flows as an
authenticated user, so leaving localhost must be deliberate:

```bash
CDT_QA_ALLOW_REMOTE=1 npm run test:e2e   # staging only. Never production.
```

## Run

```bash
npm run test:e2e                # chromium only; APP defaults to example-app
npm run test:e2e:all            # chromium + firefox + webkit
APP=example-admin npm run test:e2e
npm run typecheck
npm run report                  # opens the last HTML report
```

Traces, videos, failure screenshots and `results.json` land in
`$CDT_QA_ARTIFACTS`, defaulting to `.claude/qa/web/<runid>/`.

## Add an app

1. Copy `apps/example-app.ts` to `apps/<your-id>.ts`; set `id`, `baseURL`,
   `routes`, `roles` (env var *names*, never values) and every `selectors` entry.
2. Register it in `apps/index.ts` (one line).
3. `APP=<your-id> npm run test:e2e`.

Set `testIdAttribute` if the app uses something other than `data-testid`.

## Add a flow

Add a file under `flows/`, take `(page, app, ...)`, and reach elements through
`locate(page, app, '<logicalName>')`. New logical names go in the `SelectorName`
union in `apps/types.ts` — every app config then fails to compile until it maps
them, which is deliberate.

## House rules

- **Selectors:** `role` → `label` → `text` → `testId`, in that order. No XPath,
  no coordinates — neither survives a layout change or asserts anything a user
  can perceive.
- **Validation is DOM- and accessibility-based.** No pixel or visual diffing;
  screenshots are failure evidence only.
- **Console and network are asserted.** Specs import `test` from
  `support/console.ts`; a test that logs a JS error or sees a 5xx fails even if
  its assertions passed. Opt out per test with
  `test.use({ allowedPageIssues: [/pattern/] })`, or per app via
  `allowedPageIssues` — keep both lists short and justified.
- **Auth:** the `setup` project signs each role in once into `.auth/`; specs pick
  a role with `test.use({ storageState: storageStateFor(app, 'admin') })`.
- Wait on web-first assertions (`toBeVisible`, `toHaveCount`), never a timeout.
- Retries are configured once, in `playwright.config.ts`.
- Credentials come from `.env.qa` (gitignored) and nowhere else. Never point a
  CRUD suite at production.
