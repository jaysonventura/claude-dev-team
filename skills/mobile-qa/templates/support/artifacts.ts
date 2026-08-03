import { mkdir, writeFile } from 'node:fs/promises'
import path from 'node:path'

import { browser } from '@wdio/globals'

/** Shared with the `cdt-mobile-qa` CLI, which reads artifacts from the same var. */
export const ARTIFACTS_ENV_VAR = 'CDT_MQA_ARTIFACTS'
const ARTIFACTS_ROOT = path.join('.claude', 'mobile-qa')

/** A fresh run directory. Called once by wdio.conf.ts, then exported via env. */
export const newRunDir = (): string =>
  path.join(ARTIFACTS_ROOT, new Date().toISOString().replace(/[:.]/g, '-'))

export const artifactsDir = (): string =>
  process.env[ARTIFACTS_ENV_VAR] ?? path.join(ARTIFACTS_ROOT, 'local')

interface LogEntry {
  readonly timestamp?: number
  readonly level?: string
  readonly message?: string
}

const formatLogcat = (entries: readonly LogEntry[]): string =>
  entries
    .map((entry) => `${entry.timestamp ?? ''} ${entry.level ?? ''} ${entry.message ?? ''}`.trim())
    .join('\n')

const slug = (title: string): string =>
  title
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, '-')
    .replace(/^-+|-+$/g, '')
    .slice(0, 80) || 'test'

/**
 * Begin recording the screen for the test about to run. Never throws — a driver
 * that cannot record must not fail the suite. Call from `beforeTest`.
 */
export async function startRecording(): Promise<void> {
  try {
    await browser.startRecordingScreen()
  } catch {
    // Emulators without a media codec, or a driver that lacks the command.
  }
}

/**
 * Stop recording. Writes the mp4 only when the test FAILED — a video per passing
 * test would fill the disk for no reason. Always stops, so the next test starts clean.
 */
async function stopRecording(base: string, failed: boolean): Promise<string | null> {
  try {
    const b64 = await browser.stopRecordingScreen()
    if (!failed || !b64) return null
    await writeFile(`${base}.mp4`, Buffer.from(b64, 'base64'))
    return `${base}.mp4`
  } catch {
    return null
  }
}

/**
 * Screenshot + logcat window + the screen recording, for a failed test. Never
 * throws: a broken capture must not replace the real failure with a confusing one.
 */
export async function captureFailure(title: string): Promise<void> {
  const dir = artifactsDir()
  const base = path.join(dir, slug(title))
  const written: string[] = []

  try {
    await mkdir(dir, { recursive: true })
    await browser.saveScreenshot(`${base}.png`)
    written.push('png')
    const entries = (await browser.getLogs('logcat')) as LogEntry[]
    await writeFile(`${base}.logcat.txt`, formatLogcat(entries), 'utf8')
    written.push('logcat.txt')
  } catch (error) {
    console.error(`[mobile-qa] artifact capture failed for "${title}":`, error)
  }

  if ((await stopRecording(base, true)) !== null) written.push('mp4')
  console.log(
    written.length > 0
      ? `[mobile-qa] artifacts for "${title}" -> ${base}.{${written.join(',')}}`
      : `[mobile-qa] NO artifacts captured for "${title}" — the failure has no evidence attached`,
  )
}

/** Discard the recording for a passing test (keeps the driver clean). */
export async function discardRecording(): Promise<void> {
  try {
    await browser.stopRecordingScreen()
  } catch {
    /* nothing was recording */
  }
}
