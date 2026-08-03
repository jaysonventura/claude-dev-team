import { expect, type Page } from '@playwright/test'

import type { AppConfig } from '../apps/types.js'
import { locate } from '../support/selectors.js'

export interface FormInput {
  readonly name?: string
  readonly notes?: string
}

/** Navigate to the item list and open a blank form. */
export async function openItemForm(page: Page, app: AppConfig): Promise<void> {
  await page.goto(app.routes.items)
  await locate(page, app, 'createButton').click()
  await expect(locate(page, app, 'itemNameField')).toBeVisible()
}

/**
 * Fill the fields that were supplied and submit. Omitting `name` is how the
 * required-field case is expressed — see `expectFormRejected`.
 */
export async function fillAndSubmitForm(
  page: Page,
  app: AppConfig,
  input: FormInput,
): Promise<void> {
  if (input.name !== undefined) {
    await locate(page, app, 'itemNameField').fill(input.name)
  }
  if (input.notes !== undefined) {
    await locate(page, app, 'itemNotesField').fill(input.notes)
  }
  await locate(page, app, 'saveButton').click()
}

export async function expectFormAccepted(page: Page, app: AppConfig): Promise<void> {
  await expect(locate(page, app, 'successMessage')).toBeVisible()
  await expect(locate(page, app, 'validationError')).toBeHidden()
}

/** Submitting an empty required field must be refused, not silently accepted. */
export async function expectFormRejected(page: Page, app: AppConfig): Promise<void> {
  await expect(locate(page, app, 'validationError')).toBeVisible()
  await expect(locate(page, app, 'successMessage')).toBeHidden()
}
