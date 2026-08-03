import { expect, type Page } from '@playwright/test'

import type { AppConfig } from '../apps/types.js'
import { locate } from '../support/selectors.js'

/**
 * Upload a file and prove the SERVER accepted it, not merely that the filename
 * appeared in the DOM.
 *
 * `setInputFiles` works on a real `<input type="file">` even when CSS hides it —
 * no need to click the styled label.
 */
export async function uploadFile(page: Page, app: AppConfig, filePath: string): Promise<void> {
  await page.goto(app.routes.files)
  await locate(page, app, 'fileInput').setInputFiles(filePath)

  // Bind to the response BEFORE the click that triggers it, then assert the status.
  // A green toast with a failed POST behind it is the exact false pass this harness exists to catch.
  const uploaded = page.waitForResponse(
    (response) => response.request().method() === 'POST' && response.url().includes(app.routes.files),
  )
  await locate(page, app, 'uploadButton').click()
  const response = await uploaded
  // 2xx OR 3xx — same reason as createItem: a server-rendered app answers an upload with a 303
  // redirect, which `response.ok()` (200-299) rejects.
  expect(
    response.status() >= 200 && response.status() < 400,
    `upload POST returned ${response.status()}`,
  ).toBe(true)

  await expect(locate(page, app, 'uploadedFileMarker')).toBeVisible()
}

/**
 * Download a file and assert on the payload.
 *
 * The listener must exist BEFORE the click: `await click()` then
 * `waitForEvent('download')` races the browser and flakes. Note the deliberate
 * un-awaited promise.
 */
export async function downloadFile(page: Page, app: AppConfig): Promise<string> {
  await page.goto(app.routes.files)

  const downloadPromise = page.waitForEvent('download')
  await locate(page, app, 'downloadButton').click()
  const download = await downloadPromise

  const path = await download.path()
  expect(path, 'the browser reported a download with no file behind it').toBeTruthy()
  return download.suggestedFilename()
}
