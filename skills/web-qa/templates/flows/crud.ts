import { expect, type Locator, type Page } from '@playwright/test'

import type { AppConfig } from '../apps/types.js'
import { locate } from '../support/selectors.js'

export interface Item {
  readonly name: string
}

const escapeForRegExp = (value: string): string => value.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')

/**
 * The row for an item, found by the text a user would read rather than by index
 * — a positional row breaks the moment the list sorts differently.
 *
 * EXACT, not substring. `hasText: 'Widget'` is a case-insensitive *substring* match, so after a
 * rename to `Widget (renamed)` the old row still "matches" and an absence assertion
 * (`toHaveCount(0)`) can never pass. Anchoring the regex makes identity mean identity.
 */
const row = (page: Page, app: AppConfig, item: Item): Locator =>
  locate(page, app, 'itemRow').filter({
    hasText: new RegExp(`^\\s*${escapeForRegExp(item.name)}\\s*$`),
  })

export async function openItemList(page: Page, app: AppConfig): Promise<void> {
  await page.goto(app.routes.items)
}

export async function createItem(page: Page, app: AppConfig, item: Item): Promise<void> {
  await locate(page, app, 'createButton').click()
  await locate(page, app, 'itemNameField').fill(item.name)

  // Bind to the write BEFORE the click, then assert the server actually accepted it. Checking only
  // the rendered row passes when the UI updates optimistically and the POST failed.
  const saved = page.waitForResponse(
    (response) => response.request().method() === 'POST' && response.url().includes(app.routes.items),
  )
  await locate(page, app, 'saveButton').click()
  const response = await saved
  expect(response.ok(), `create returned ${response.status()}`).toBe(true)

  await expect(row(page, app, item)).toBeVisible()
}

/**
 * Frontend state is not backend truth. A reload discards every bit of client state, so what survives
 * it genuinely persisted — this is what separates "the row appeared" from "the record exists".
 */
export async function expectPersisted(page: Page, app: AppConfig, item: Item): Promise<void> {
  await page.reload()
  await expect(row(page, app, item)).toBeVisible()
}

export async function renameItem(
  page: Page,
  app: AppConfig,
  item: Item,
  newName: string,
): Promise<void> {
  await locate(row(page, app, item), app, 'editButton').click()
  await locate(page, app, 'itemNameField').fill(newName)
  await locate(page, app, 'saveButton').click()

  await expect(row(page, app, { name: newName })).toBeVisible()
  await expect(row(page, app, item)).toHaveCount(0)
}

export async function deleteItem(page: Page, app: AppConfig, item: Item): Promise<void> {
  await locate(row(page, app, item), app, 'deleteButton').click()
  await locate(page, app, 'confirmButton').click()
  await expect(row(page, app, item)).toHaveCount(0)
}

export async function expectListEmpty(page: Page, app: AppConfig): Promise<void> {
  await expect(locate(page, app, 'emptyState')).toBeVisible()
}
