# Scenario playbooks

Eleven web workflows. Each runs after `cdt-web-qa doctor` is green, in a **fresh browser context**
(no shared storage state). **Every scenario ends with the console + network check** — a green UI with a
console exception or a failed XHR is a FAIL. Capture on failure: `browser_take_screenshot` +
`browser_console_messages` + `browser_network_requests` + the `browser_snapshot` at the failing step,
plus the trace from the harness run.

---

## 1 · Authentication (login / logout)

**Pre:** fresh context; creds from env / `.env.qa` (never inline). The app's `baseURL` must be loopback —
the harness throws otherwise unless `CDT_QA_ALLOW_REMOTE=1` is set deliberately. **Never against production.**
**Steps:** `browser_navigate` → `browser_snapshot` → `getByLabel('Email').fill()` /
`getByLabel('Password').fill()` (MCP: `browser_fill_form`) → `getByRole('button', { name: 'Sign in' })`
click → `await expect(page).toHaveURL(/\/dashboard/)` → assert an authed landmark → open the account menu
→ log out.
**Assert:** the authed landmark is visible; `toHaveURL` matches; after logout the login form is back
**and** `browser_navigate_back` does not restore the authed page (session actually cleared, not just
routed away); the session cookie is gone from `context.storageState()`.
**Fail capture:** snapshot at the failing step + the auth request from `browser_network_requests`
(**scrub the token before it goes in any report**).
**Web trap:** the **`storageState` is saved before the session cookie lands.** In a `setup` project,
`page.getByRole('button', { name: 'Sign in' }).click()` returns before the redirect completes — saving
immediately writes an auth file with no cookie, and every dependent project then fails as "logged out".
Save only *after* `await expect(authedLandmark).toBeVisible()`.

## 2 · Role-based access

**Pre:** one `storageState` file **per role** (`admin.json`, `user.json`), each produced by its own setup
test; a URL only the higher role may reach.
**Steps:** for each role, load its state via `test.use({ storageState })` → navigate to the privileged
route → snapshot → attempt the privileged action.
**Assert:** allowed role sees and can use the control; denied role gets a real denial — **assert the
HTTP status, not only the missing UI**: `page.waitForResponse(r => r.url().includes('/api/admin'))` →
`expect(r.status()).toBe(403)`. Also assert the denied role cannot reach it by direct URL.
**Fail capture:** the snapshot for the denied role + the network entry for the privileged call.
**Web trap:** **one auth file reused for two roles.** `storageState` is a file path, so a copy-pasted
project or a shared `playwright/.auth/user.json` silently runs the "user" tests as admin — every
authorization assertion passes for the wrong reason. Second trap: an app that renders the admin nav and
hides it with CSS/JS passes a UI-only check while the API is wide open. The 403 assertion is what makes
this scenario real.

## 3 · Forms & validation

**Pre:** fresh context; navigate to the form; know the required-field set.
**Steps:** submit empty (validation path) → fill one field at a time and blur → submit valid → submit one
boundary value (max length, unicode, leading/trailing space, `<script>`).
**Assert:** per-field messages appear and are **associated with their input** (`getByLabel(...)` →
`toHaveAccessibleDescription` or the error text scoped to the field group); the valid case produces the
success state; `toHaveValue()` matches what was typed; the POST body matches the typed values; no console
error on any path.
**Fail capture:** snapshot of the field group + the POST from `browser_network_requests`.
**Web trap:** **the success toast auto-dismisses before you assert it.** A 3-second toast plus a chained
`await` in front of the assertion loses the race, and it fails only on a loaded CI machine. Either assert
it as the very next statement (`expect` auto-retries from the moment it is called, it does not rewind),
or — better — assert the durable effect instead of the toast. Second trap: `getByLabel('Email')` matching
both a filter box and the form field → strict-mode violation; scope it (see `selectors.md`).

## 4 · CRUD

**Pre:** fresh context; authenticated; a known-empty or seeded list.
**Steps:** create with a unique marker string (`qa-${Date.now()}`) → find it in the list → open → update a
field → return → delete → confirm the destructive dialog.
**Assert:** the row appears / updates / disappears, **and survives `await page.reload()`**; the write
request returned 2xx; the delete actually 404s or is absent on a direct `request.get()` of the resource.
**Fail capture:** the list snapshot before/after + the write request/response pair.
**Web trap:** **optimistic UI.** The row is pushed into local state the instant you click Save and is
rendered before — sometimes *despite* — the failing POST. The assertion passes, the data never persisted.
The reload is the assertion. Second trap: a virtualized/paginated list means "not found" often means "not
rendered" — filter or search for the marker rather than scanning the DOM.

## 5 · Search / filter / sort

**Pre:** fresh context; a dataset with a known result count for at least one query.
**Steps:** type a query → wait for the results to settle → apply a filter → apply a sort → clear
everything → check the URL reflects the state (if the app uses query params) and that a reload restores
it.
**Assert:** `await expect(rows).toHaveCount(n)` (auto-retrying — this is the wait); the first/last row
matches the sort key; combined filter+sort narrows correctly; clearing restores the baseline count; the
search request fired once per settled query, not once per keystroke.
**Fail capture:** the results snapshot + every `/search` request from `browser_network_requests` with its
status and query string.
**Web trap:** **debounce plus `networkidle`.** Typing fires the request ~300 ms later, so an assertion
immediately after `fill()` reads the *previous* result set — and `waitForLoadState('networkidle')` is
explicitly discouraged and never settles on an app that polls or holds a websocket. Use the retrying
`toHaveCount`, or `page.waitForResponse(r => r.url().includes('/search'))` scoped to that call.

## 6 · File upload / download

**Pre:** fresh context; a small fixture file committed under the harness; a writable artifacts dir.
**Steps — upload:** `page.getByLabel('Upload file').setInputFiles(path)` for a real `<input type=file>`
(MCP: `browser_file_upload`). For a custom button that has no input, register the listener first:
`const fileChooserPromise = page.waitForEvent('filechooser')` — **no `await`** — then click, then
`(await fileChooserPromise).setFiles(path)`.
**Steps — download:** `const downloadPromise = page.waitForEvent('download')` — **no `await`** — then
click, then `const download = await downloadPromise` →
`await download.saveAs(dir + download.suggestedFilename())`.
**Assert:** upload shows the filename and a 2xx to the upload endpoint; oversize/wrong-type files are
rejected with a readable message and no 500; the downloaded file exists, is non-zero, and
`suggestedFilename()` is what the app promised.
**Fail capture:** snapshot + the upload/download request entries.
**Web trap:** **the event listener must exist before the click.** `await page.click(...)` then
`await page.waitForEvent('download')` misses the event that already fired and hangs until timeout — the
canonical "downloads don't work in Playwright" bug, and it is always the test. Same shape for
`filechooser`. Second trap: `setInputFiles` needs the actual `<input>`; on a drag-and-drop dropzone the
input is often `display:none` — target it directly, it does not need to be visible.

## 7 · Payment / transaction

**Pre:** **SANDBOX ONLY.** Test-mode processor keys from env. Only production credentials available →
**refuse the scenario and report it** (`qa-shared` security table).
**Steps:** add a documented test card → review → confirm → wait for the result page → verify the record
in the app's own order/history view **and** via `request.get('/api/orders/<id>')`.
**Assert:** success state plus a reference id; the processor's declined test PAN yields a clear declined
state, not a crash or a blank page; double-clicking Confirm creates exactly **one** order (check the
network log for a single POST); no console error during the redirect back from the processor.
**Fail capture:** snapshot + trace, **with card fields and tokens scrubbed** before anything is pasted.
**Web trap:** **the card fields are in a cross-origin iframe.** Stripe/Adyen/Braintree mount their inputs
in an iframe, so a top-level `getByLabel('Card number')` finds nothing and reads as "the field is
missing". Use `page.frameLocator('iframe[name^="__privateStripeFrame"]').getByLabel('Card number')`.
Second trap: the 3DS step opens in a **new tab or a nested iframe** — handle it (`browser_tabs` /
`context.on('page')`), don't assume the flow stays on one page.

## 8 · API error handling

**Pre:** fresh context; a way to force failures — prefer `page.route()` over a fixture account.
**Steps:** `await page.route('**/api/orders', route => route.fulfill({ status: 500, body: '{}' }))`
**before** the action → trigger it → observe the UI → `await page.unroute('**/api/orders')` → retry →
let it succeed. Repeat for 401, 422 and `route.abort()` (network drop).
**Assert:** a **user-readable** error appears (no raw stack, no silent no-op); the app stays usable; the
retry succeeds; **no duplicate write** was created by the failed attempt (verify server-side); the 401
path lands on login rather than looping.
**Fail capture:** the error surface snapshot + the full request list showing the forced status and the
retry.
**Web trap:** **routes are context-scoped and sticky.** Registering the route after the navigation that
already fired the request does nothing; and forgetting `unroute()` makes the "recovery" step hit the same
stub, so the retry appears to fail and you file a bug against working code. Second trap: `route.abort()`
and a 500 exercise *different* app paths — a `catch` that handles a rejected fetch often does not handle
a resolved-but-500 response. Test both.

## 9 · Responsive UI

**Pre:** fresh context; the flow already passing at desktop width.
**Steps:** run the flow at **375×667**, **768×1024**, **1280×720** — `browser_resize` live, or
`test.use({ viewport })` / a device preset per project. At each width: open the nav, reach every
interactive control in the flow, submit.
**Assert:** every control in the flow is visible and clickable at that width; the collapsed nav opens and
its links work; no horizontal overflow —
`browser_evaluate` → `document.documentElement.scrollWidth <= document.documentElement.clientWidth`;
text is not truncated where it must be readable. **No pixel comparison, no visual baseline.**
**Fail capture:** the snapshot at that viewport + the overflow measurement + a screenshot as human
evidence only.
**Web trap:** **both navs are in the DOM.** Most responsive apps render the desktop nav *and* the mobile
drawer and hide one with CSS, so `getByRole('link', { name: 'Settings' })` resolves to 2 elements and
throws a strict-mode violation that looks like a duplicate-content bug. Disambiguate with
`.filter({ visible: true })` or by scoping to the visible `<nav>` — **not** `.nth(0)`, which silently
picks the hidden one at the other breakpoint. Second trap: `browser_resize` does not re-run media queries
that were evaluated during a JS-driven layout on load; if the app measures on mount, resize **then**
reload.

## 10 · Cross-browser

**Pre:** the flow green on chromium; all three engines installed (`cdt-web-qa browsers --install`).
**Steps:** `cdt-web-qa test --browser firefox`, then `--browser webkit`. For any failure, re-run that one
spec on that one engine with the trace open.
**Assert:** identical functional outcomes on all three. Differences to expect and check deliberately:
native date/time inputs, `<select>` rendering, clipboard, autoplay/media, file-input behaviour, focus
order, smooth-scroll, and cookie/`SameSite` handling on auth redirects.
**Fail capture:** the failing engine's trace + console + network, and the chromium run of the same spec
side by side.
**Web trap:** **treating a webkit-only failure as flake and re-running until green.** WebKit is Safari;
an engine-specific failure is a real, user-visible bug — file it with the engine named. The inverse trap:
some failures are the *test*, not the app — `context.grantPermissions` (clipboard, geolocation) is
Chromium-only and throws during setup on firefox/webkit, which reads like an app crash. Confirm which
side is engine-dependent before you file.

## 11 · Session & permission

**Pre:** fresh context; an authenticated session; the browser-permission-requiring feature identified
(geolocation, camera, clipboard, notifications).
**Steps:** open a second tab on the same context (`browser_tabs` / `context.newPage()`) → log out in
tab 2 → act in tab 1. Then: expire or clear the session cookie mid-flow and act. Then: exercise the
permission prompt path — granted (`context.grantPermissions([...])`), and denied/never-granted (default,
no grant).
**Assert:** tab 1 detects the dead session on its next action — redirect to login or a clear message,
never a silent 401 loop or a blank screen; the expired-session case does not lose unsaved input without
warning; the granted permission path works; the denied path shows an explanatory state and does not
crash; no uncaught exception in either path.
**Fail capture:** snapshots of **both** tabs + the 401 responses from the network log.
**Web trap:** **a stale `storageState` file.** The saved auth state is a snapshot; once the backend
rotates sessions, invalidates on deploy, or shortens TTL, every dependent project starts its first
request with a dead cookie and the whole suite fails as a wave of 401s that looks like an app auth
regression. Re-run the `setup` project (or delete the auth file) before believing it. Second trap:
permission APIs are context-scoped and **not** reset between tests in the same context — grant in one
test and the "denied" test inherits the grant.
