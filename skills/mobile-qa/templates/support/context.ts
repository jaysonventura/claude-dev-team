import { browser } from '@wdio/globals'

import type { AppConfig } from '../apps/types.js'

export const NATIVE_CONTEXT = 'NATIVE_APP'

const WEBVIEW_ATTACH_TIMEOUT_MS = 20_000
const WEBVIEW_POLL_INTERVAL_MS = 500

/** `getContexts()` yields names by default, objects when asked for detail. */
type ContextEntry = string | { readonly id: string }

export const webviewContextName = (app: AppConfig): string =>
  app.webviewContext ?? `WEBVIEW_${app.appPackage}`

/**
 * Wait for the app's webview to actually attach. Switching straight after
 * launch is the classic Capacitor flake: the context exists a beat later.
 */
export async function waitForWebviewContext(app: AppConfig): Promise<string> {
  const wanted = webviewContextName(app)
  let seen: string[] = []

  await browser.waitUntil(
    async () => {
      const contexts = (await browser.getContexts({
        waitForWebviewMs: WEBVIEW_POLL_INTERVAL_MS,
        filterByCurrentAndroidApp: true,
      })) as ContextEntry[]
      seen = contexts.map((entry) => (typeof entry === 'string' ? entry : entry.id))
      return seen.includes(wanted)
    },
    {
      timeout: WEBVIEW_ATTACH_TIMEOUT_MS,
      interval: WEBVIEW_POLL_INTERVAL_MS,
      timeoutMsg: `Webview "${wanted}" never attached. Contexts seen: ${seen.join(', ') || '(none)'}`,
    },
  )

  return wanted
}

/** Run `fn` against the DOM, then always hand the session back to native. */
export async function inWebview<T>(app: AppConfig, fn: () => Promise<T>): Promise<T> {
  const context = await waitForWebviewContext(app)
  await browser.switchContext(context)
  try {
    return await fn()
  } finally {
    await browser.switchContext(NATIVE_CONTEXT)
  }
}

/**
 * Run a flow against whichever layer owns this app's UI. Capacitor apps live in
 * the webview; React Native and native apps are driven natively.
 */
export async function withUi<T>(app: AppConfig, fn: () => Promise<T>): Promise<T> {
  return app.kind === 'capacitor' ? inWebview(app, fn) : fn()
}
