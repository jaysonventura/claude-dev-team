// Must come first: app configs read their base URL from the environment at
// module load, so `.env.qa` has to be in place before they are evaluated.
import { assertSafeTarget } from '../support/env.js'

import { app as exampleAdmin } from './example-admin.js'
import { app as exampleApp } from './example-app.js'
import type { AppConfig } from './types.js'

/** Add a new app: create `apps/<id>.ts`, then add one line here. */
export const apps: Readonly<Record<string, AppConfig>> = {
  [exampleApp.id]: exampleApp,
  [exampleAdmin.id]: exampleAdmin,
}

export const DEFAULT_APP = exampleApp.id

/** The app under test, selected by `APP=<id>`. Imported by playwright.config.ts and the specs. */
export function currentApp(): AppConfig {
  const id = process.env.APP ?? DEFAULT_APP
  const app = apps[id]

  if (app === undefined) {
    throw new Error(`Unknown APP "${id}". Known: ${Object.keys(apps).join(', ')}`)
  }

  // Enforced at the single chokepoint every spec and the config already route through, so no app
  // config and no new spec can opt out of it by forgetting to call it.
  assertSafeTarget(app.id, app.baseURL)

  return app
}
