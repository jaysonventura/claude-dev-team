import path from 'node:path'

/** Shared with the `cdt-web-qa` CLI, which reads artifacts from the same var. */
export const ARTIFACTS_ENV_VAR = 'CDT_QA_ARTIFACTS'

/** Matches the layout in `skills/qa-shared/SKILL.md`: `.claude/qa/<platform>/<runid>`. */
const ARTIFACTS_ROOT = path.join('.claude', 'qa', 'web')

const newRunId = (): string => new Date().toISOString().replace(/[:.]/g, '-')

/**
 * The run directory for this process. `cdt-web-qa` sets the env var so its run
 * id wins; a bare `npm run test:e2e` gets a fresh timestamped directory.
 *
 * Call once, in playwright.config.ts, then export the result back into the env
 * so every worker and reporter writes to the same place.
 */
export function artifactsDir(): string {
  return process.env[ARTIFACTS_ENV_VAR] ?? path.join(ARTIFACTS_ROOT, newRunId())
}

/** Traces, videos and failure screenshots. Playwright writes one folder per test here. */
export const testResultsDir = (runDir: string): string => path.join(runDir, 'test-results')

/** Machine-readable run summary, for the CLI and for CI. */
export const resultsJsonPath = (runDir: string): string => path.join(runDir, 'results.json')

/**
 * Browser storage state per app+role. Session cookies and tokens — gitignored,
 * and deliberately outside the artifacts root so a run-dir cleanup does not
 * force every role to log in again.
 */
export const storageStatePath = (appId: string, role: string): string =>
  path.join('.auth', `${appId}-${role}.json`)
