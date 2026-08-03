# Scenario playbooks

Eight shared workflows. Each runs after `doctor` is green. **`reset <pkg>` before every scenario** —
no shared state. Capture on every failure: `shot` + `logcat --pkg <pkg> --since <step-start>` + `ui`.

---

## 1 · Login / logout

**Pre:** `reset <pkg>`; `launch <pkg>`; creds from `.env.qa` (never inline).
**Steps:** `ui --json` → locate the username field by `resource-id` → `sel(app,'usernameField')` fill →
password fill → submit → wait for the post-login landmark element (not a sleep) → open menu → logout.
**Assert:** landmark element present after login; auth token stored; after logout the login screen is back
**and** back-navigation does not return to the authed screen (session actually cleared).
**Fail capture:** screenshot at the failing step + logcat filtered for the auth call (scrub the token).
**Android trap:** the **soft keyboard covers the submit button**. Dismiss it (`hideKeyboard` / back) before
tapping submit, or scroll the button into view — a tap on a keyboard-covered button silently hits the key.

## 2 · Form submission

**Pre:** `reset <pkg>`; navigate to the form; know the required-field set.
**Steps:** fill each field via `by.testId()`; submit empty first (validation path), then valid, then one
boundary value (max length, unicode, leading space).
**Assert:** per-field validation messages appear for the empty case; the success state/toast appears for
the valid case; the submitted payload matches what was typed.
**Fail capture:** `ui --json` for the field showing the wrong value + logcat around the POST.
**Android trap:** **autocorrect/predictive text rewrites typed input**. Assert the field's actual value
after typing, not just that typing happened. Multi-line and IME-composed text are the usual offenders.

## 3 · Navigation

**Pre:** `reset <pkg>`; app at its start destination.
**Steps:** walk each tab/stack entry; push 2+ deep; return via the in-app back control; repeat the return
via the **hardware back button**; rotate the device mid-stack.
**Assert:** the correct screen landmark after each hop; back returns to the exact previous screen with its
state intact; the app does not exit from a nested screen.
**Fail capture:** `ui` dump at the wrong destination + the current activity from logcat.
**Android trap:** **hardware back ≠ in-app back.** Many apps wire only one. Test both — hardware back
exiting the app from a detail screen is a real, commonly shipped bug.

## 4 · CRUD

**Pre:** `reset <pkg>`; authenticated; a known-empty or seeded list.
**Steps:** create an item with a unique marker string → read it back in the list → open it → update a field
→ return to list → delete → confirm the destructive dialog.
**Assert:** the item appears/updates/disappears in the list **and** survives a kill + relaunch
(`stop <pkg>` then `launch <pkg>`) — proves persistence, not just local view state.
**Fail capture:** list `ui` dump before/after + logcat for the write call.
**Android trap:** **list virtualization** — the new item exists but is off-screen and never rendered.
Scroll to it before asserting absence; "not found" in a RecyclerView usually means "not scrolled to".

## 5 · API error handling

**Pre:** `reset <pkg>`; a way to force a server error (test-mode flag, error-triggering fixture account).
**Steps:** trigger the failing call → observe the UI → retry the action → let it succeed.
**Assert:** a **user-readable** error is shown (not a raw stack or silent no-op); the app stays usable;
retry works; no duplicate write was created by the failed attempt.
**Fail capture:** the raw error surface in `ui` + the logcat window for the failing request.
**Android trap:** the error path fires while a **loading spinner is still animating** — the assertion races
the transition. Wait for the spinner element to disappear, never a fixed sleep.

## 6 · Payment / transaction

**Pre:** **SANDBOX ONLY.** Test-mode processor keys from `.env.qa`. If only production credentials exist,
**refuse the scenario and report it** — do not run it.
**Steps:** add a test card (processor's documented test PAN) → review → confirm → wait for the result
screen → verify the record in the app's history.
**Assert:** success state and receipt/reference id; the declined test card produces a clear declined state,
not a crash; no double charge on a double-tap of confirm.
**Fail capture:** screenshot + logcat **with card and token fields scrubbed** before it goes in any report.
**Android trap:** the processor SDK opens a **WebView or Custom Tab** — UiAutomator2 cannot see the DOM in
`NATIVE_APP` context. Switch to `WEBVIEW_<pkg>` (see `selectors.md`) or the fields will look "missing".

## 7 · Offline / network failure

**Pre:** `reset <pkg>`; app launched and warm.
**Steps:** `cdt-mobile-qa net off` → perform a read, then a write → `net on` → observe recovery.
**Assert:** an offline indicator or clear error appears; cached content still renders; queued writes either
sync on reconnect or are clearly reported as failed — **never silently dropped**; no crash.
**Fail capture:** `logcat --crash` + screenshot of the offline state.
**Android trap:** **stale connections after `net on`** — the app's HTTP client holds a dead socket and the
first retry fails regardless of app quality. Retry once after reconnect before calling it a bug, and say
that you did.

## 8 · Permission handling

**Pre:** `reset <pkg>` (clears granted permissions too); do **not** pre-grant for this scenario.
**Steps:** trigger the permission-requiring feature → handle the system dialog (allow) → re-`reset` →
trigger again → **deny** → trigger again → **deny permanently** ("Don't allow" twice).
**Assert:** granted path works; denied path shows an explanatory in-app state and does not crash;
permanently-denied path offers a route to system settings.
**Fail capture:** `ui` dump showing which dialog was on screen + logcat for the permission result.
**Android trap:** the **system permission dialog steals focus** and belongs to a different package, so a
selector scoped to the app finds nothing. Query the dialog's own `resource-id`
(`com.android.permissioncontroller:id/...`) or use `perm grant` to bypass the dialog when the dialog itself
is not what you are testing.
