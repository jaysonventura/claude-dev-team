import { existsSync } from 'node:fs'

/**
 * Load `.env.qa` before anything reads `process.env`.
 *
 * `apps/index.ts` imports this first, so app configs (which read their base URL
 * at module load) already see it. ES modules evaluate imports in source order —
 * that ordering is load-bearing, do not move this import below the app imports.
 *
 * Node >= 20.12 for `loadEnvFile`; on older Node, export the variables yourself.
 */
if (existsSync('.env.qa') && typeof process.loadEnvFile === 'function') {
  process.loadEnvFile('.env.qa')
}

const LOOPBACK = /^https?:\/\/(localhost|127\.0\.0\.1|\[::1\]|0\.0\.0\.0)(:\d+)?(\/|$)/i

/**
 * Leaving localhost must be DELIBERATE.
 *
 * The suite runs destructive scenarios — CRUD creates and deletes, payment flows — as an
 * authenticated admin. A single environment variable is otherwise all that stands between a test run
 * and production data. Prose in a skill file is not a control: this throws.
 *
 * Staging is legitimate. Set `CDT_QA_ALLOW_REMOTE=1` to say so out loud.
 */
export function assertSafeTarget(appId: string, baseURL: string): void {
  if (LOOPBACK.test(baseURL) || process.env.CDT_QA_ALLOW_REMOTE === '1') {
    return
  }

  throw new Error(
    `[web-qa] Refusing to run against a non-loopback target for app "${appId}": ${baseURL}\n` +
      `This suite performs destructive actions (create/update/DELETE, payment flows) as an ` +
      `authenticated user. Point it at a local or disposable environment, or — if this target is ` +
      `genuinely a throwaway staging environment and NOT production — re-run with ` +
      `CDT_QA_ALLOW_REMOTE=1 to confirm deliberately.`,
  )
}
