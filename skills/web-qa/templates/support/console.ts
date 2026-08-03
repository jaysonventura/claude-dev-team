import { test as base, expect } from '@playwright/test'

import { currentApp } from '../apps/index.js'

/**
 * The harness's teeth: a page that logged a JS error or served a 5xx fails the
 * test, even if every assertion passed. Capturing without asserting is how a
 * suite stays green while the app throws on every page load.
 *
 * Specs import `test`/`expect` from HERE, not from `@playwright/test` — that
 * import is what installs the check.
 */

export interface PageIssueOptions {
  /**
   * Per-test opt-out for a failure this test legitimately expects, e.g. a spec
   * that deliberately drives the API into a 500:
   *
   * ```ts
   * test.use({ allowedPageIssues: [/\/api\/checkout/] })
   * ```
   *
   * Unions with the app's own `allowedPageIssues` rather than replacing it.
   */
  allowedPageIssues: readonly RegExp[]
}

/** 4xx counts too: a 401/403/404 the app did not expect is a real defect, not noise. Legitimate
 *  negative-path tests opt out per-test via `allowedPageIssues`. */
const CLIENT_ERROR_STATUS = 400

/**
 * Attachments land in the HTML report; keep credentials out of them.
 *
 * The scheme word must be consumed too. `authorization[=:\s]+\S+` matched only "Bearer" in
 * `Authorization: Bearer eyJ…`, so the redaction ate the harmless word and published the JWT.
 */
// The optional prefix matters: `\btoken\b` cannot match inside `access_token` (an underscore is a
// word character), so `?access_token=<jwt>` sailed through un-redacted.
const CREDENTIAL_KEY = /\b((?:[A-Za-z0-9]+[_-])?(?:authorization|bearer|token|api[-_]?key|cookie|set-cookie))\b/
const CREDENTIAL_VALUE = /[A-Za-z0-9._~+/=-]{16,}/

/**
 * Two branches, because credentials appear in two shapes and an earlier single-branch attempt broke
 * one while fixing the other:
 *  - `key: value` / `key=value` — always redact, whatever the value looks like.
 *  - `key value` / `key/value`  — redact ONLY when the value is credential-shaped (>=16 chars of
 *    token alphabet). Without that guard, "token expired, please sign in" gets eaten.
 * The value run stops at whitespace, `;` or `,`, so `Cookie: a=1; session=SECRET` redacts BOTH pairs
 * rather than only the first.
 */
const redact = (line: string): string =>
  line.replace(
    new RegExp(
      CREDENTIAL_KEY.source +
        '(?:\\s*[:=]\\s*|[\\s/]+(?=(?:bearer\\s+|basic\\s+)?' +
        CREDENTIAL_VALUE.source +
        '))(?:bearer\\s+|basic\\s+)?[^\\s;,]+',
      'gi',
    ),
    '$1: <redacted>',
  )
    // Remaining `k=v` pairs inside a cookie/query string, so only the first pair is not redacted.
    .replace(/([;&]\s*)[A-Za-z0-9._-]+=[A-Za-z0-9._~+/=-]{16,}/g, '$1<redacted>')

export const test = base.extend<PageIssueOptions & { failOnPageIssues: void }>({
  allowedPageIssues: [[], { option: true }],

  failOnPageIssues: [
    async ({ page, allowedPageIssues }, use, testInfo): Promise<void> => {
      const allowed = [...(currentApp().allowedPageIssues ?? []), ...allowedPageIssues]
      const isAllowed = (line: string): boolean => allowed.some((pattern) => pattern.test(line))

      /** Fails the test. */
      const failures: string[] = []
      /** Reported as evidence but never fails. */
      const notes: string[] = []

      const record = (into: string[], line: string): void => {
        const entry = redact(line)
        if (!isAllowed(entry)) into.push(entry)
      }

      page.on('console', (message) => {
        if (message.type() !== 'error') return
        const text = message.text()
        // Chromium logs a SECOND line for every failing request — "Failed to load resource: the
        // server responded with a status of 401" — carrying no URL and no `http NNN:` prefix. The
        // `response` handler below already records that exact event WITH its URL, so this line is a
        // duplicate that no `allowedPageIssues` pattern can target. Keeping it made every deliberate
        // 4xx test unconditionally fail.
        if (/^Failed to load resource:/.test(text)) return
        record(failures, `console.error: ${text}`)
      })
      page.on('pageerror', (error) => {
        record(failures, `pageerror: ${error.message}`)
      })
      page.on('response', (response) => {
        if (response.status() >= CLIENT_ERROR_STATUS) {
          record(failures, `http ${response.status()}: ${response.url()}`)
        }
      })
      page.on('requestfailed', (request) => {
        const reason = request.failure()?.errorText ?? 'unknown'
        const line = `request failed: ${request.url()} (${reason})`
        // A request that never completed is normally a failure: the UI can render a cached or empty
        // state and look correct while its data call died.
        //
        // ERR_ABORTED is the exception, and it is not rare. Every DOWNLOAD is an aborted navigation,
        // so failing on it made the download test unconditionally fail. The same code covers a
        // navigation the user cancelled by clicking away. Recorded as evidence, never fatal.
        record(reason.includes('ERR_ABORTED') ? notes : failures, line)
      })

      await use()

      const all = [...failures, ...notes]
      if (all.length > 0) {
        await testInfo.attach('page-issues', { body: all.join('\n'), contentType: 'text/plain' })
      }

      // A test that already failed keeps its own failure — replacing it with ours
      // would hide the assertion that actually broke.
      if (testInfo.status !== testInfo.expectedStatus) return

      expect(failures, 'the browser reported errors while this test was passing').toEqual([])
    },
    { auto: true },
  ],
})

export { expect }
