import { existsSync } from 'node:fs'

import { currentApp } from './apps/index.js'
import {
  ARTIFACTS_ENV_VAR,
  captureFailure,
  discardRecording,
  newRunDir,
  startRecording,
} from './support/artifacts.js'

// Credentials + device overrides. Node >= 20.12 only; on older Node, export them yourself.
if (existsSync('.env.qa') && typeof process.loadEnvFile === 'function') {
  process.loadEnvFile('.env.qa')
}

// Set once in the launcher so every worker and the Appium log land in the same run dir.
const artifactsDir = process.env[ARTIFACTS_ENV_VAR] ?? newRunDir()
process.env[ARTIFACTS_ENV_VAR] = artifactsDir

const app = currentApp()
const deviceName = app.deviceName ?? process.env.ANDROID_DEVICE ?? 'Android Emulator'
const platformVersion = app.platformVersion ?? process.env.ANDROID_PLATFORM_VERSION

export const config: WebdriverIO.Config = {
  runner: 'local',
  specs: ['./specs/**/*.e2e.ts'],
  maxInstances: 1,

  hostname: process.env.APPIUM_HOST ?? '127.0.0.1',
  port: Number(process.env.APPIUM_PORT ?? 4723),

  capabilities: [
    {
      platformName: 'Android',
      // Lowercase per the uiautomator2-driver README ("Must be set to 'uiautomator2'").
      // Case-insensitive at runtime — do not "correct" this to UiAutomator2.
      'appium:automationName': 'uiautomator2',
      'appium:deviceName': deviceName,
      ...(platformVersion === undefined ? {} : { 'appium:platformVersion': platformVersion }),

      // With an apk we install fresh; without one we attach to the installed build.
      ...(app.apkPath === undefined
        ? { 'appium:noReset': true }
        : { 'appium:app': app.apkPath, 'appium:noReset': false }),
      'appium:appPackage': app.appPackage,
      'appium:appActivity': app.appActivity,

      'appium:autoGrantPermissions': true,
      'appium:disableWindowAnimation': true,
      'appium:newCommandTimeout': 120,
    },
  ],

  // Starts a local Appium server for the run. Point `hostname`/`port` at a
  // remote grid and drop this service if you already have one running.
  services: [['appium', { logPath: artifactsDir }]],

  framework: 'mocha',
  reporters: ['spec'],
  mochaOpts: { ui: 'bdd', timeout: 120_000 },

  logLevel: 'warn',
  bail: 0,

  // Every wait is an explicit condition; never a fixed pause.
  waitforTimeout: 15_000,
  connectionRetryTimeout: 180_000,
  connectionRetryCount: 3,

  // The single retry knob. Raising it hides flake — fix the flake instead.
  specFileRetries: 1,
  specFileRetriesDelay: 0,

  onPrepare(): void {
    console.log(`[mobile-qa] app=${app.id} device=${deviceName} artifacts=${artifactsDir}`)
  },

  async beforeTest(): Promise<void> {
    // Record every test; the mp4 is only written for one that fails.
    await startRecording()
  },

  async afterTest(test, _context, result): Promise<void> {
    if (result.passed) {
      await discardRecording()
      return
    }
    await captureFailure(`${test.parent} ${test.title}`)
  },
}
