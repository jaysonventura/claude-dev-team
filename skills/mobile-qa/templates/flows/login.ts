import { $, expect } from '@wdio/globals'

import type { AppConfig } from '../apps/types.js'
import { withUi } from '../support/context.js'
import { sel } from '../support/selectors.js'

export interface Credentials {
  readonly username: string
  readonly password: string
}

/** Credentials live in `.env.qa` (gitignored) and nowhere else. */
export function credentialsFromEnv(): Credentials {
  const username = process.env.QA_USERNAME
  const password = process.env.QA_PASSWORD

  if (username === undefined || password === undefined || username === '' || password === '') {
    throw new Error('QA_USERNAME and QA_PASSWORD must be set — copy .env.qa.example to .env.qa')
  }

  return { username, password }
}

async function submitCredentials(app: AppConfig, credentials: Credentials): Promise<void> {
  await $(sel(app, 'usernameField')).waitForDisplayed()
  await $(sel(app, 'usernameField')).setValue(credentials.username)
  await $(sel(app, 'passwordField')).setValue(credentials.password)
  await $(sel(app, 'submitButton')).click()
}

export async function login(app: AppConfig, credentials: Credentials): Promise<void> {
  await withUi(app, async () => {
    await submitCredentials(app, credentials)
    await expect($(sel(app, 'homeMarker'))).toBeDisplayed()
  })
}

/** Negative path: bad credentials surface an error and never reach home. */
export async function expectLoginRejected(app: AppConfig, credentials: Credentials): Promise<void> {
  await withUi(app, async () => {
    await submitCredentials(app, credentials)
    await expect($(sel(app, 'errorBanner'))).toBeDisplayed()
    await expect($(sel(app, 'homeMarker'))).not.toBeDisplayed()
  })
}
