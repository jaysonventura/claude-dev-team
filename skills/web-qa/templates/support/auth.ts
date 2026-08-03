import type { AppConfig, UserRole } from '../apps/types.js'
import { storageStatePath } from './artifacts.js'

export interface Credentials {
  readonly username: string
  readonly password: string
}

/**
 * Credentials live in the environment (`.env.qa`, gitignored) and nowhere else.
 * The app config names the two variables; only the process holds the values.
 */
export function credentialsFor(app: AppConfig, role: UserRole): Credentials {
  const { usernameEnv, passwordEnv } = app.roles[role]
  const username = process.env[usernameEnv]
  const password = process.env[passwordEnv]

  if (username === undefined || username === '' || password === undefined || password === '') {
    throw new Error(
      `${usernameEnv} and ${passwordEnv} must be set for role "${role}" of app "${app.id}" — ` +
        'copy .env.qa.example to .env.qa and fill them in.',
    )
  }

  return { username, password }
}

/**
 * Where the signed-in browser state for this app+role is cached.
 *
 * The `setup` project signs each role in once and writes this file; every test
 * project then starts already authenticated via `storageState`. Role-based
 * access tests therefore cost one login per run, not one per test.
 */
export const storageStateFor = (app: AppConfig, role: UserRole): string =>
  storageStatePath(app.id, role)
