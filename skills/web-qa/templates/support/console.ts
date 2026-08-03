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
const redact = (line: string): string =>
  line.replace(
    // The separator is REQUIRED. With `[:=]?` optional this ate ordinary prose —
    // "token expired, please sign in" became "token <redacted> please sign in".
    /\b(authorization|bearer|token|api[-_]?key|cookie|set-cookie)\b\s*[:=]\s*(bearer\s+|basic\s+)?\S+/gi,
    '$1: <redacted>',
  )

export const test = base.extend<PageIssueOptions & { failOnPageIssues: void }>({
  allowedPageIssues: [[], { option: true }],

  failOnPageIssues: [
    async ({ page, allowedPageIssues }, use, testInfo): Promise<void> => {
      const allowed = [...(currentApp().allowedPageIssues ?? []), ...allowedPageIssues]
      const isAllowed = (line: string): boolean => allowed.some((pattern) => pattern.test(line))

      /** Fails the test. */
      const failures: string[] = []
      /** Reported as evidence but never fails: aborted and cancelled requests are routine. */
      const notes: string[] = []

      const record = (into: string[], line: string): void => {
        const entry = redact(line)
        if (!isAllowed(entry)) into.push(entry)
      }

      page.on('console', (message) => {
        if (message.type() === 'error') record(failures, `console.error: ${message.text()}`)
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
        // A request that never completed is a failure, not a note: the UI may render a cached or
        // empty state and look correct while its data call died. `allowedPageIssues` covers the
        // deliberate offline/abort scenarios.
        record(failures, `request failed: ${request.url()} (${request.failure()?.errorText ?? 'unknown'})`)
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
