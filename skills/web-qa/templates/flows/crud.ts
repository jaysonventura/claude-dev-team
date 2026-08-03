import { expect, type Locator, type Page } from '@playwright/test'

import type { AppConfig } from '../apps/types.js'
import { locate } from '../support/selectors.js'

export interface Item {
  readonly name: string
}

/**
 * The row for an item, found by the text a user would read rather than by index
 * — a positional row breaks the moment the list sorts differently.
 *
 * Substring, deliberately. A row is a CONTAINER: the flows below scope `editButton` / `deleteButton`
 * inside it, so its text content is `My itemEditDelete`. An anchored regex would therefore match
 * nothing at all. The corollary is on the caller: an absence assertion only means something when the
 * new name is not a superstring of the old one — see `renameItem`.
 */
const row = (page: Page, app: AppConfig, item: Item): Locator =>
  locate(page, app, 'itemRow').filter({ hasText: item.name })

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
  // The old-row-is-gone assertion below is a substring match, so a new name CONTAINING the old one
  // (`Widget` -> `Widget (renamed)`) can never satisfy it. Fail loudly here rather than leaving a
  // caller to debug an assertion that was unsatisfiable from the start.
  if (newName.includes(item.name)) {
    throw new Error(
      `renameItem: "${newName}" contains the old name "${item.name}". Rows match by substring, so ` +
        `the old row would still match after the rename. Use a name that is not a superstring.`,
    )
  }

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
