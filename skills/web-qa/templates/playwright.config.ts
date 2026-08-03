import { defineConfig, devices } from '@playwright/test'

import { currentApp } from './apps/index.js'
import { ARTIFACTS_ENV_VAR, artifactsDir, resultsJsonPath, testResultsDir } from './support/artifacts.js'

// Resolved once in the config so every worker and reporter writes to one run dir,
// then exported so the cdt-web-qa CLI and the specs read the same value.
const runDir = artifactsDir()
process.env[ARTIFACTS_ENV_VAR] = runDir

const app = currentApp()
const isCI = process.env.CI !== undefined && process.env.CI !== ''

/** Chromium/Firefox/WebKit share everything except the browser. */
const browserProject = (name: string, device: string) => ({
  name,
  testMatch: /\.e2e\.ts$/,
  use: { ...devices[device] },
  dependencies: ['setup'],
})

export default defineConfig({
  testDir: './specs',
  // Traces, videos and failure screenshots. Honours CDT_QA_ARTIFACTS.
  outputDir: testResultsDir(runDir),

  timeout: 60_000,
  // Every wait is an assertion with a deadline; never a fixed sleep.
  expect: { timeout: 10_000 },

  fullyParallel: true,
  forbidOnly: isCI,
  workers: isCI ? 1 : undefined,

  // The single retry knob. Raising it hides flake — fix the flake instead.
  retries: isCI ? 1 : 0,

  reporter: [
    ['list'],
    ['html', { outputFolder: 'playwright-report', open: 'never' }],
    // Machine-readable summary for the CLI and CI.
    ['json', { outputFile: resultsJsonPath(runDir) }],
  ],

  use: {
    baseURL: app.baseURL,
    testIdAttribute: app.testIdAttribute,

    // Evidence for failures only — a trace per passing test fills a disk, and
    // captures carry session tokens. Never used for pixel comparison.
    trace: 'retain-on-failure',
    video: 'retain-on-failure',
    screenshot: 'only-on-failure',
  },

  projects: [
    // Signs each role in once and writes .auth/<app>-<role>.json.
    { name: 'setup', testMatch: /auth\.setup\.ts$/ },

    browserProject('chromium', 'Desktop Chrome'),
    browserProject('firefox', 'Desktop Firefox'),
    browserProject('webkit', 'Desktop Safari'),
  ],
})
