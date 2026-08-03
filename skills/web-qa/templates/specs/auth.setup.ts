import { currentApp } from '../apps/index.js'
import type { UserRole } from '../apps/types.js'
import { signIn } from '../flows/auth.js'
import { credentialsFor, storageStateFor } from '../support/auth.js'
import { test as setup } from '../support/console.js'

/**
 * Runs once per run, before the browser projects. Each role signs in and its
 * cookies/localStorage are saved, so the specs start authenticated instead of
 * replaying a login form for every test.
 *
 * Uses the strict `test` from support/console.ts on purpose: a sign-in page
 * that throws is a real bug, and failing here fails loudly before any spec runs.
 */

const app = currentApp()
const roles: readonly UserRole[] = ['user', 'admin']

for (const role of roles) {
  setup(`authenticate ${app.name} as ${role}`, async ({ page }) => {
    await signIn(page, app, credentialsFor(app, role))
    await page.context().storageState({ path: storageStateFor(app, role) })
  })
}
