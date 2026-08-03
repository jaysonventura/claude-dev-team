import { $, expect } from '@wdio/globals'

import type { AppConfig } from '../apps/types.js'
import { withUi } from '../support/context.js'
import { sel } from '../support/selectors.js'

export interface FormInput {
  readonly name: string
  readonly notes?: string
}

/** Fill the item form and submit. Leaves the app wherever submit lands it. */
export async function fillAndSubmitForm(app: AppConfig, input: FormInput): Promise<void> {
  await withUi(app, async () => {
    await $(sel(app, 'itemNameField')).waitForDisplayed()
    await $(sel(app, 'itemNameField')).setValue(input.name)

    if (input.notes !== undefined) {
      await $(sel(app, 'itemNotesField')).setValue(input.notes)
    }

    await $(sel(app, 'submitButton')).click()
  })
}

export async function expectFormAccepted(app: AppConfig): Promise<void> {
  await withUi(app, async () => {
    await expect($(sel(app, 'successBanner'))).toBeDisplayed()
  })
}

/** Submitting an empty required field must be rejected, not silently accepted. */
export async function expectFormRejected(app: AppConfig): Promise<void> {
  await withUi(app, async () => {
    await expect($(sel(app, 'errorBanner'))).toBeDisplayed()
    await expect($(sel(app, 'successBanner'))).not.toBeDisplayed()
  })
}
