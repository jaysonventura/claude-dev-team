import { expect, type Page } from '@playwright/test'

import type { AppConfig } from '../apps/types.js'
import type { Credentials } from '../support/auth.js'
import { locate } from '../support/selectors.js'

/** Fill the sign-in form and submit it. Leaves the app wherever submit lands it. */
async function submitCredentials(
  page: Page,
  app: AppConfig,
  credentials: Credentials,
): Promise<void> {
  await page.goto(app.routes.signIn)
  await locate(page, app, 'usernameField').fill(credentials.username)
  await locate(page, app, 'passwordField').fill(credentials.password)
  await locate(page, app, 'signInButton').click()
}

export async function signIn(page: Page, app: AppConfig, credentials: Credentials): Promise<void> {
  await submitCredentials(page, app, credentials)
  await expect(locate(page, app, 'signedInMarker')).toBeVisible()
}

/** Negative path: bad credentials surface an error and never reach the signed-in UI. */
export async function expectSignInRejected(
  page: Page,
  app: AppConfig,
  credentials: Credentials,
): Promise<void> {
  await submitCredentials(page, app, credentials)
  await expect(locate(page, app, 'signInError')).toBeVisible()
  await expect(locate(page, app, 'signedInMarker')).toBeHidden()
}

/** The admin area is reachable for a role that owns it. */
export async function expectAdminAreaVisible(page: Page, app: AppConfig): Promise<void> {
  await page.goto(app.routes.adminOnly)
  await expect(locate(page, app, 'adminAreaMarker')).toBeVisible()
}

/**
 * ...and refused for one that does not. Asserting the refusal marker alone is
 * not enough — a page can render "not authorized" above the real content — so
 * the admin marker must also be absent.
 */
export async function expectAdminAreaRefused(page: Page, app: AppConfig): Promise<void> {
  await page.goto(app.routes.adminOnly)
  await expect(locate(page, app, 'accessDeniedMarker')).toBeVisible()
  await expect(locate(page, app, 'adminAreaMarker')).toBeHidden()
}
