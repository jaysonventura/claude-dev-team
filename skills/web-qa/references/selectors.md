# Selector policy

A locator is only as stable as the thing it names. **Semantics are stable; markup is not.**

## Priority order (use the first that works)

| # | Locator | Real syntax | Use when |
|---|---------|-------------|----------|
| 1 | **`getByRole()`** | `page.getByRole('button', { name: 'Sign in' })` | **Default for every interactive element.** Buttons, links, inputs, checkboxes, headings, dialogs, tabs, rows. |
| 2 | **`getByLabel()`** | `page.getByLabel('Email address')` | Form fields — matches the `<label>`, `aria-label` or `aria-labelledby` a user actually reads |
| 3 | **`getByText()`** | `page.getByText('Order confirmed', { exact: true })` | Non-interactive copy: messages, toasts, empty states. Prefer `exact: true` |
| 4 | **`getByTestId()`** | `page.getByTestId('order-row')` | The escape hatch — only when semantics genuinely do not identify the element |

Other first-class options when they fit the intent: `getByPlaceholder()`, `getByAltText()`,
`getByTitle()` — all above `getByTestId` in spirit, all below `getByLabel` in reliability.

**Forbidden, except as a documented last resort:** XPath, and coordinate-based interaction
(`page.mouse.click(x, y)`, `dispatchEvent` on a point). Also never select on a CSS class, a DOM index, or
a position in a list — those change with every restyle.

```ts
// XPath: the vendor rich-text toolbar renders no role, name, or test id on this button — filed APP-1234
await page.locator('xpath=//div[@class="tox-toolbar"]//button[3]').click()
```

No comment saying **why** → the reviewer deletes it. Every last-resort locator carries the ticket that
will remove it.

## Why `getByRole` is first

`getByRole` queries the **accessibility tree**, not the DOM. Two consequences:

1. It is the same tree `browser_snapshot` returns, so a locator derived from the snapshot is a fact, not
   a guess — and it survives markup refactors that would break any CSS selector.
2. **It doubles as an accessibility check.** If `getByRole('button', { name: 'Save' })` finds nothing,
   either the element is a `<div>` with a click handler or it has no accessible name — a real a11y defect
   the test just found for free. Fix the app; do not downgrade to a CSS selector to make the test pass.

Useful role options (all real): `name`, `exact`, `checked`, `disabled`, `expanded`, `pressed`,
`selected`, `level` (headings). `name` matches the accessible name and is case-insensitive +
whitespace-normalized unless you pass `exact: true`.

## Intent → locator

| Intent | Locator |
|--------|---------|
| Click the submit button | `page.getByRole('button', { name: 'Sign in' }).click()` |
| Fill a labelled field | `page.getByLabel('Password').fill(pw)` |
| Follow a link | `page.getByRole('link', { name: 'Settings' }).click()` |
| Toggle a checkbox | `page.getByRole('checkbox', { name: 'Remember me' }).check()` |
| Pick from a native select | `page.getByLabel('Country').selectOption('PH')` |
| Assert a message | `await expect(page.getByText('Order confirmed', { exact: true })).toBeVisible()` |
| Assert the page moved | `await expect(page).toHaveURL(/\/orders\/\d+/)` |
| One row in a table | `page.getByRole('row').filter({ hasText: 'ORD-1042' })` |
| A control **inside** that row | `page.getByRole('row').filter({ hasText: 'ORD-1042' }).getByRole('button', { name: 'Delete' })` |
| Scope to a region | `page.getByRole('navigation').getByRole('link', { name: 'Settings' })` |
| Count results | `await expect(page.getByRole('listitem')).toHaveCount(12)` |
| Semantics genuinely absent | `page.getByTestId('chart-canvas')` |

## Strict mode

Every Playwright locator is strict: if it matches more than one element, the action throws
`strict mode violation: locator resolved to 2 elements`. **That error is information, not an obstacle** —
it usually means the page really does contain two things a user could confuse, or (very often on
responsive apps) a hidden duplicate.

Disambiguate by narrowing the *intent*:

| Fix | Syntax |
|-----|--------|
| Filter by contained text | `.filter({ hasText: 'ORD-1042' })` |
| Filter by a contained element | `.filter({ has: page.getByRole('button', { name: 'Delete' }) })` |
| Exclude | `.filter({ hasNot: … })` · `.filter({ hasNotText: … })` |
| Only the visible one (responsive duplicates) | `.filter({ visible: true })` |
| Tighten the name | `getByRole('button', { name: 'Save', exact: true })` |
| Scope to a region | `page.getByRole('dialog').getByRole('button', { name: 'Save' })` |
| Genuinely "either of these" | `a.or(b).first()` — a real API, for conditional UI (a dialog that may or may not appear) |

**Do not reach for `.nth(0)` / `.first()` to silence it.** Index order is not guaranteed by anything the
user perceives, and on a responsive page the first match is frequently the *hidden* one — the test then
clicks nothing and fails somewhere unrelated three steps later. `.first()` is only correct when you have
established the matches are genuinely interchangeable (e.g. `.or()` on conditional UI).

## `data-testid` — the escape hatch

Reach for it only when no role, label, placeholder, alt text or stable copy identifies the element: a
canvas/chart, a purely decorative wrapper you must scroll, a widget whose visible text is the data under
test (asserting on it would make the locator circular), or a heavily-localized string.

`getByTestId` reads `data-testid` by default; if the app already uses another attribute, configure it
once — `use: { testIdAttribute: 'data-qa' }` in `playwright.config.ts` — rather than writing raw
attribute selectors.

**What to tell the app team** (unstable selectors are an app fix, not a cleverer locator):

1. Every interactive element needs an accessible name — a real `<button>`/`<a>`, a `<label>`, or
   `aria-label`. This fixes the tests and the screen-reader experience in one change.
2. Add `data-testid` only where semantics genuinely cannot identify the element.
3. Name the **role**, not the copy or the position: `submit-order`, not `blue-button-2`.
4. Ids must survive re-render — not generated per mount, not index-suffixed by list position.
5. Treat test ids as API: renaming one is a breaking change to the suite.

File it as a ticket and reference that ticket in the last-resort locator you had to write meanwhile.

## Auto-waiting — never sleep

Playwright already waits. Before acting, it checks the element is **visible, stable (not animating),
receiving events (not covered), enabled** — and for `fill()`, editable. Web-first assertions
(`expect(locator).…`) auto-retry until they pass or time out.

```ts
await expect(page.getByText('Welcome')).toBeVisible()   // 👍 retries until it appears
expect(await page.getByText('Welcome').isVisible()).toBe(true)   // 👎 reads once, races the render
await page.waitForTimeout(2000)                          // 👎 a flake generator
```

- **`waitForTimeout` is officially discouraged** and is the single most common cause of a suite that is
  green locally and red on CI. It is a debugging tool, never a test step.
- `waitForSelector` is likewise discouraged — use a locator action or `expect(locator).toBeVisible()`.
- `waitForLoadState('networkidle')` / `waitUntil: 'networkidle'` are discouraged too, and simply never
  settle on an app that polls or holds a websocket. Assert on the thing you actually need instead.
- Need a specific request? `page.waitForResponse(r => r.url().includes('/api/search') && r.ok())` — a
  real signal, not a guess about how long the server takes.
- Retrying matchers to prefer: `toBeVisible`, `toBeHidden`, `toBeEnabled`, `toHaveText`, `toHaveValue`,
  `toHaveCount`, `toHaveURL`, `toHaveAttribute`.
- `force: true` disables the actionability checks — it converts a real bug (a control covered by an
  overlay, a button that is genuinely disabled) into a green test. Use it only with a comment saying why,
  same rule as XPath.

## MCP refs are per-snapshot

`browser_snapshot` returns element refs that `browser_click` / `browser_type` consume. **A ref is only
valid for the snapshot that produced it** — after any navigation, re-render or route change, take a new
snapshot. A stale ref fails in a way that reads like "the element disappeared", and it is the exploratory
equivalent of an index-based selector. Snapshot → act → snapshot again.
