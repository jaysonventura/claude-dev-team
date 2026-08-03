import { $, expect } from '@wdio/globals'

import type { AppConfig } from '../apps/types.js'
import { withUi } from '../support/context.js'
import { sel } from '../support/selectors.js'

export interface Item {
  /** Row suffix — the app renders `testID={`<itemRow>-${key}`}`. */
  readonly key: string
  readonly name: string
}

const row = (app: AppConfig, item: Item): string => sel(app, 'itemRow', item.key)

export async function createItem(app: AppConfig, item: Item): Promise<void> {
  await withUi(app, async () => {
    await $(sel(app, 'createButton')).click()
    await $(sel(app, 'itemNameField')).waitForDisplayed()
    await $(sel(app, 'itemNameField')).setValue(item.name)
    await $(sel(app, 'submitButton')).click()
    await expect($(row(app, item))).toBeDisplayed()
  })
}

export async function renameItem(app: AppConfig, item: Item, newName: string): Promise<void> {
  await withUi(app, async () => {
    await $(row(app, item)).click()
    await $(sel(app, 'editButton')).click()
    await $(sel(app, 'itemNameField')).waitForDisplayed()
    await $(sel(app, 'itemNameField')).clearValue()
    await $(sel(app, 'itemNameField')).setValue(newName)
    await $(sel(app, 'submitButton')).click()
    await expect($(row(app, item))).toHaveText(expect.stringContaining(newName))
  })
}

export async function deleteItem(app: AppConfig, item: Item): Promise<void> {
  await withUi(app, async () => {
    await $(row(app, item)).click()
    await $(sel(app, 'deleteButton')).click()
    await $(sel(app, 'confirmButton')).click()
    await expect($(row(app, item))).not.toBeDisplayed()
  })
}

export async function expectListEmpty(app: AppConfig): Promise<void> {
  await withUi(app, async () => {
    await expect($(sel(app, 'emptyState'))).toBeDisplayed()
  })
}
