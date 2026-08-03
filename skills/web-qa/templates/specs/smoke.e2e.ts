import { currentApp } from '../apps/index.js'
import { expectAdminAreaRefused, expectAdminAreaVisible, expectSignInRejected } from '../flows/auth.js'
import { createItem, deleteItem, openItemList, renameItem, type Item } from '../flows/crud.js'
import { expectFormAccepted, expectFormRejected, fillAndSubmitForm, openItemForm } from '../flows/forms.js'
import { storageStateFor } from '../support/auth.js'
// `test` comes from support/console.ts, never from @playwright/test — that
// import is what makes a JS error or a 5xx fail the test.
import { test } from '../support/console.js'

const app = currentApp()

test.describe('signed out', () => {
  // Drop the signed-in state this project would otherwise start with.
  test.use({ storageState: { cookies: [], origins: [] } })

  test('refuses invalid credentials', async ({ page }) => {
    await expectSignInRejected(page, app, {
      username: 'no-such-user@example.invalid',
      password: 'deliberately-invalid',
    })
  })
})

test.describe('as a standard user', () => {
  test.use({ storageState: storageStateFor(app, 'user') })

  test('is refused the admin area', async ({ page }) => {
    await expectAdminAreaRefused(page, app)
  })

  test('creates, renames and deletes an item', async ({ page }) => {
    // Unique per run so parallel workers and repeat runs never collide.
    const item: Item = { name: `Smoke item ${Date.now()}` }

    await openItemList(page, app)
    await createItem(page, app, item)
    await renameItem(page, app, item, `${item.name} (renamed)`)
    await deleteItem(page, app, { name: `${item.name} (renamed)` })
  })

  test('accepts a valid submission', async ({ page }) => {
    await openItemForm(page, app)
    await fillAndSubmitForm(page, app, {
      name: `Form item ${Date.now()}`,
      notes: 'created by the smoke spec',
    })
    await expectFormAccepted(page, app)
  })

  test('refuses a submission missing a required field', async ({ page }) => {
    await openItemForm(page, app)
    await fillAndSubmitForm(page, app, { notes: 'no name supplied' })
    await expectFormRejected(page, app)
  })
})

test.describe('as an admin', () => {
  test.use({ storageState: storageStateFor(app, 'admin') })

  test('reaches the admin area', async ({ page }) => {
    await expectAdminAreaVisible(page, app)
  })
})
