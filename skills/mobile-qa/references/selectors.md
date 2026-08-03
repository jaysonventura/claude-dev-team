# Selector policy

A selector is only as stable as the thing it names. Names are stable; layout is not.

## Precedence (use the first that works)

| # | Strategy | WDIO | When |
|---|----------|------|------|
| 1 | **Accessibility id** (`content-desc`) | `by.testId('x')` → `~x` | Default. Works on both platforms. |
| 2 | **Resource id** | `by.resourceId('x')` → `android=new UiSelector().resourceIdMatches("^(?:.+:id/)?x$")` | RN `testID` lands here; the regex matches bare **and** package-prefixed ids |
| 3 | **UiSelector by text/class** | `android=new UiSelector().text("Save")` | Only when no id exists **and** the text is not localized |
| 4 | **XPath** | `//android.widget.Button[@text="Save"]` | **Last resort only** |

**In a flow, never call `by.*` directly — call `sel(app, '<logicalName>')`.** `sel()` is the one place
that knows how each app kind exposes ids (`react-native` → `by.resourceId`, `native` → `by.testId`,
`capacitor` → a DOM `[data-testid]` valid only inside the webview). Calling `by.testId` directly in a
flow hardcodes the *native* strategy and silently matches nothing on an RN app.

**XPath rule:** every XPath in the repo carries a one-line comment saying **why** no id was available.

```ts
// XPath: vendor payment SDK ships no resource-id or content-desc on this button — filed APP-1234
await $('//android.widget.Button[@text="Confirm"]').click()
```

No comment → the reviewer deletes it. XPath is also the slowest strategy and the first to break on any
layout change.

Never select on: absolute coordinates, index position in a list, or a class name alone.

## React Native

| RN prop | Android attribute | Query as |
|---------|-------------------|----------|
| `testID` | `resource-id` | `by.testId('submit')` |
| `accessibilityLabel` | `content-desc` | `~submit` |

**Caveat:** on Android these two collide. Depending on the RN version and the component, setting
`accessibilityLabel` can override what lands in `content-desc`, and on some versions `testID` is mapped to
`content-desc` instead of `resource-id` when accessibility is enabled on the view. **Do not assume — dump
the tree** (`cdt-mobile-qa ui --json`) and read which attribute actually carries your value, per component
type. Assert against what the dump shows, not what the JSX says.

Jetpack Compose equivalent: `Modifier.testTag()` only reaches `resource-id` when the app enables
`testTagsAsResourceId`. If tags are missing from the dump, that flag is off — that is an app-team fix.

## Ionic / Capacitor (WebView apps)

The app is a WebView. **`data-testid` is invisible to UiAutomator2 in `NATIVE_APP` context** — the whole
DOM appears as one opaque `android.webkit.WebView` node. You must switch context.

```ts
// Enumerate what's actually attached
const contexts = await driver.getContexts()
// → ['NATIVE_APP', 'WEBVIEW_com.example.app']

await driver.switchContext(`WEBVIEW_com.example.app`)   // now CSS selectors work
await $('[data-testid="submit"]').click()
await driver.switchContext('NATIVE_APP')                 // back for native dialogs/permissions
```

Verified against WebdriverIO docs (context7, wdio 9.30.1): `driver.getContexts()` accepts options
(`returnDetailedContexts`, `filterByCurrentAndroidApp`, `androidWebviewConnectTimeout`, `waitForWebviewMs`);
`driver.switchContext()` accepts a context-name string **or** an options object with `title` / `url` /
`appIdentifier` — use the object form when the webview has multiple pages, since Android webviews commonly
do and the plain name form picks an arbitrary one. Appium-level equivalent: `mobile: getContexts`.

**Rules for hybrid apps:**

- System dialogs (permissions, payment sheets, share) are **native** — switch back to `NATIVE_APP` first.
- Switch back before taking `ui` dumps; the dump is a native-context operation.
- Set `appium:autoWebview` only when the app is webview-only start to finish; otherwise switch explicitly.

**Chromedriver pitfall:** the WebView context needs a Chromedriver matching the device's **System WebView**
version — a mismatch fails the switch with a version error, not a "not found" error. Fixes, in order:
`appium:chromedriverExecutableDir` pointed at a directory of versioned drivers, or
`appium:chromedriverChromeMappingFile`. Update the device's Android System WebView and the driver together.

## What to tell the app team

When selectors are unstable, the fix belongs in the app, not in a cleverer XPath. Ask for:

1. A stable id on every interactive element in the flow — RN `testID`, Compose `testTag` +
   `testTagsAsResourceId`, Ionic `data-testid`.
2. Ids that name the **role**, not the copy or the position (`submit-order`, not `blue-button-2`).
3. Ids that survive re-render — not generated per mount.
4. Ids treated as API: renaming one is a breaking change to the test suite.

File it as a ticket and reference the ticket in the XPath comment you had to write in the meantime.
