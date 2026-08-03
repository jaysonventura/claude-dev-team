import { currentApp } from '../apps/index.js'
import { expectAdminAreaRefused, expectAdminAreaVisible, expectSignInRejected } from '../flows/auth.js'
import {
  createItem,
  deleteItem,
  expectPersisted,
  openItemList,
  renameItem,
  type Item,
} from '../flows/crud.js'
import { downloadFile, uploadFile } from '../flows/files.js'
import { expectFormAccepted, expectFormRejected, fillAndSubmitForm, openItemForm } from '../flows/forms.js'
import { storageStateFor } from '../support/auth.js'
// `test` comes from support/console.ts, never from @playwright/test — that
// import is what makes a JS error or a 5xx fail the test.
import { expect, test } from '../support/console.js'

const app = currentApp()

test.describe('signed out', () => {
  // Drop the signed-in state this project would otherwise start with.
  test.use({ storageState: { cookies: [], origins: [] } })

  // A rejected sign-in IS a 4xx. The harness fails any >=400 by default, so a deliberate
  // negative path must say so — that is what `allowedPageIssues` is for.
  test.use({ allowedPageIssues: [/http 40[013]: .*(sign-?in|login|auth)/i] })

  test('refuses invalid credentials', async ({ page }) => {
    await expectSignInRejected(page, app, {
      username: 'no-such-user@example.invalid',
      password: 'deliberately-invalid',
    })
  })
})

test.describe('as a standard user', () => {
  test.use({ storageState: storageStateFor(app, 'user') })

  // The 403 IS the assertion here (references/scenarios.md section 2), so this one test opts out of
  // the >=400 rule. Scoped to its own describe so the CRUD tests below stay strict.
  test.describe('admin route', () => {
    test.use({ allowedPageIssues: [/http 40[13]: /] })

    test('is refused the admin area', async ({ page }) => {
      await expectAdminAreaRefused(page, app)
    })
  })

  test('creates, renames and deletes an item', async ({ page }) => {
    // Unique per run so parallel workers and repeat runs never collide.
    const stamp = Date.now()
    const item: Item = { name: `Smoke item ${stamp}` }
    // NOT a superstring of the original: rows match by substring, so `${name} (renamed)` would leave
    // the old row still matching and the "old row is gone" assertion could never pass.
    const renamed: Item = { name: `Renamed item ${stamp}` }

    await openItemList(page, app)
    await createItem(page, app, item)
    // Frontend state is not backend truth — prove it survived a reload before mutating further.
    await expectPersisted(page, app, item)
    await renameItem(page, app, item, renamed.name)
    await deleteItem(page, app, renamed)
  })

  test('accepts a valid submission', async ({ page }) => {
    await openItemForm(page, app)
    await fillAndSubmitForm(page, app, {
      name: `Form item ${Date.now()}`,
      notes: 'created by the smoke spec',
    })
    await expectFormAccepted(page, app)
  })

  // Server-side validation answers 400/422 by design — again, opt out narrowly rather than
  // weakening the rule for the whole suite.
  test.describe('validation', () => {
    test.use({ allowedPageIssues: [/http 4(00|22): /] })

    test('refuses a submission missing a required field', async ({ page }) => {
      await openItemForm(page, app)
      await fillAndSubmitForm(page, app, { notes: 'no name supplied' })
      await expectFormRejected(page, app)
    })
  })

  test('uploads a file and downloads it back', async ({ page }) => {
    // A real file from the harness itself — no fixture to keep in sync.
    await uploadFile(page, app, new URL('../package.json', import.meta.url).pathname)
    const name = await downloadFile(page, app)
    expect(name.length, 'the download had no filename').toBeGreaterThan(0)
  })
})

test.describe('as an admin', () => {
  test.use({ storageState: storageStateFor(app, 'admin') })

  test('reaches the admin area', async ({ page }) => {
    await expectAdminAreaVisible(page, app)
  })
})
