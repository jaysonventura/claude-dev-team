// The ONLY trusted verification source: .claude/runtime/verify-events.jsonl.
//
//   verification = 'failed'   if any cdt-verify event has exitCode > 0
//                = 'passed'    else if >=1 cdt-verify event has exitCode === 0
//                = 'not_run'   else (only hook-sourced / null / no events)
//
// `cdt-verify -- <cmd>` is the only producer of a real (non-null) exitCode. The PostToolUse hook writes
// best-effort events with exitCode:null (source:"hook"), which can never produce 'passed'.

import { spawnSync } from 'node:child_process';
import { join } from 'node:path';
import { appendJsonl, readJsonl } from '../utils/io.js';
import { projectRoot, runtimeDir } from '../utils/paths.js';
import type { VerificationState, VerifyEvent, VerifyType } from '../utils/types.js';

export function eventsPath(root: string = projectRoot()): string {
  return join(runtimeDir(root), 'verify-events.jsonl');
}

export function readVerifyEvents(root: string = projectRoot()): VerifyEvent[] {
  return readJsonl<VerifyEvent>(eventsPath(root));
}

export function appendVerifyEvent(ev: VerifyEvent, root: string = projectRoot()): void {
  appendJsonl(eventsPath(root), ev, root);
}

export function classifyVerifyType(command: string): VerifyType {
  const c = command.toLowerCase();
  if (/typecheck|type-check|tsc\s+--noemit|tsc\s+--no-emit|mypy/.test(c)) return 'typecheck';
  if (/\blint\b|eslint|flake8|shellcheck|ruff/.test(c)) return 'lint';
  if (/\btest\b|vitest|jest|pytest|mocha|\bspec\b|go test/.test(c)) return 'test';
  if (/\bbuild\b|tsc\b|compile|webpack|vite build|rollup|esbuild|make\b/.test(c)) return 'build';
  return 'other';
}

export function computeVerification(events: VerifyEvent[]): VerificationState {
  const trusted = events.filter((e) => e.source === 'cdt-verify' && typeof e.exitCode === 'number');
  if (trusted.some((e) => (e.exitCode as number) > 0)) return 'failed';
  if (trusted.some((e) => e.exitCode === 0)) return 'passed';
  return 'not_run';
}

/** True when the session ran verify-like commands only via the best-effort hook (no cdt-verify evidence). */
export function hasHookOnlyEvidence(events: VerifyEvent[]): boolean {
  const hook = events.some((e) => e.source === 'hook');
  const trusted = events.some((e) => e.source === 'cdt-verify');
  return hook && !trusted;
}

export interface VerifyRun {
  exitCode: number;
  type: VerifyType;
  command: string;
}

/** Run a command, capture its real exit code, and record a trusted verify event. */
export function runVerify(commandParts: string[], root: string = projectRoot(), nowIso?: string): VerifyRun {
  const command = commandParts.join(' ');
  const type = classifyVerifyType(command);
  const res = spawnSync(command, { shell: true, stdio: 'inherit', cwd: root });
  const exitCode = typeof res.status === 'number' ? res.status : 1;
  appendVerifyEvent(
    {
      ts: nowIso ?? new Date().toISOString(),
      command,
      type,
      exitCode,
      cwd: root,
      source: 'cdt-verify',
    },
    root,
  );
  return { exitCode, type, command };
}
