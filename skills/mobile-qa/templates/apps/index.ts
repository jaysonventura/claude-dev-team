import { app as exampleCapacitor } from './example-capacitor.js'
import { app as exampleRn } from './example-rn.js'
import type { AppConfig } from './types.js'

/** Add a new app: create `apps/<id>.ts`, then add one line here. */
export const apps: Readonly<Record<string, AppConfig>> = {
  [exampleRn.id]: exampleRn,
  [exampleCapacitor.id]: exampleCapacitor,
}

export const DEFAULT_APP = exampleRn.id

/** The app under test, selected by `APP=<id>`. Imported by wdio.conf.ts and the specs. */
export function currentApp(): AppConfig {
  const id = process.env.APP ?? DEFAULT_APP
  const app = apps[id]

  if (app === undefined) {
    throw new Error(`Unknown APP "${id}". Known: ${Object.keys(apps).join(', ')}`)
  }

  return app
}
