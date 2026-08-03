import { currentApp } from '../apps/index.js'
import { createItem, deleteItem, expectListEmpty, renameItem, type Item } from '../flows/crud.js'
import { expectFormAccepted, fillAndSubmitForm } from '../flows/form.js'
import { credentialsFromEnv, expectLoginRejected, login } from '../flows/login.js'

const app = currentApp()
const item: Item = { key: `smoke-${Date.now()}`, name: 'Smoke item' }

describe(`${app.name} smoke`, () => {
  it('rejects bad credentials', async () => {
    await expectLoginRejected(app, { username: 'not-a-user', password: 'not-a-password' })
  })

  it('logs in with valid credentials', async () => {
    await login(app, credentialsFromEnv())
  })

  it('accepts a valid form submission', async () => {
    await fillAndSubmitForm(app, { name: item.name, notes: 'created by the smoke spec' })
    await expectFormAccepted(app)
  })

  it('creates, renames and deletes an item', async () => {
    await createItem(app, item)
    await renameItem(app, item, `${item.name} (renamed)`)
    await deleteItem(app, item)
    await expectListEmpty(app)
  })
})
