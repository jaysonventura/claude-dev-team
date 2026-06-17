// Local-only TASK_RESULT.json builder + the Stop-hook finalize. verification is ALWAYS derived from
// verify-events (never trusted from free text). The 6-field final-response format is enforced as a
// reminder string.

import { join } from 'node:path';
import { editedPaths } from '../utils/git.js';
import { readJson, writeArtifact } from '../utils/io.js';
import { claudeDir, projectRoot } from '../utils/paths.js';
import type { CdtConfig, RoutingResult, TaskResult, TaskStatus, VerificationState, VerifyEvent } from '../utils/types.js';
import { redact } from '../validators/redact.js';
import { validateTaskResult } from '../validators/validate.js';
import { computeVerification, hasHookOnlyEvidence, readVerifyEvents } from '../verify/events.js';

export function taskResultPath(root: string = projectRoot()): string {
  return join(claudeDir(root), 'TASK_RESULT.json');
}

export function isDocsOnly(paths: string[]): boolean {
  if (paths.length === 0) return false;
  return paths.every((p) => p.includes('.claude/plans/') || /\.(md|markdown)$/i.test(p));
}

function deriveStatus(v: VerificationState, docsOnly: boolean): TaskStatus {
  if (v === 'failed') return 'failed';
  if (v === 'passed') return 'done';
  return docsOnly ? 'done' : 'partial';
}

function deriveNextStep(v: VerificationState): string {
  if (v === 'failed') return 'Fix the failing verification command and re-run via `cdt-verify -- <cmd>`.';
  if (v === 'passed') return 'Review the change and open a PR.';
  return 'Run the verifying command via `cdt-verify -- <cmd>` to record trusted evidence.';
}

export interface TaskResultInput {
  status?: TaskStatus;
  task?: string;
  result?: string;
  artifact?: string | null;
  nextStep?: string;
}

export function buildTaskResult(input: TaskResultInput, verification: VerificationState, cfg: CdtConfig, docsOnly = false): TaskResult {
  const red = (s: string): string => (cfg.redact ? redact(s) : s);
  return {
    status: input.status ?? deriveStatus(verification, docsOnly),
    task: red((input.task ?? 'unspecified task').slice(0, 200)) || 'unspecified task',
    result: red((input.result ?? '').slice(0, 400)) || (verification === 'passed' ? 'Verified.' : 'See artifacts.'),
    verification,
    artifact: input.artifact ?? null,
    nextStep: red((input.nextStep ?? deriveNextStep(verification)).slice(0, 300)),
  };
}

function taskFromRouting(root: string): string {
  const rt = readJson<RoutingResult>(join(claudeDir(root), 'ROUTING.json'));
  if (rt?.promptRedacted) return rt.promptRedacted.split('\n')[0]?.slice(0, 120) ?? 'task';
  return 'unspecified task';
}

export interface FinalizeOutcome {
  taskResult: TaskResult;
  verification: VerificationState;
  events: VerifyEvent[];
  hookOnly: boolean;
  docsOnly: boolean;
  degraded: boolean;
}

/**
 * Stop-hook finalize: compute verification from evidence, keep an agent-authored result's prose but
 * OVERRIDE its verification, otherwise synthesize a minimal result. Always writes TASK_RESULT.json.
 */
export function finalizeTaskResult(
  cfg: CdtConfig,
  root: string = projectRoot(),
  opts: { editedPaths?: string[] } = {},
): FinalizeOutcome {
  const events = readVerifyEvents(root);
  const verification = computeVerification(events);
  const paths = opts.editedPaths ?? editedPaths(root);
  const docsOnly = isDocsOnly(paths);

  const existing = readJson<unknown>(taskResultPath(root));
  let degraded = false;
  let input: TaskResultInput;
  if (existing && validateTaskResult(existing).valid) {
    const e = existing as TaskResult;
    input = { status: e.status, task: e.task, result: e.result, artifact: e.artifact, nextStep: e.nextStep };
  } else {
    if (existing) degraded = true; // present but invalid → synthesize, flag
    input = { task: taskFromRouting(root) };
  }

  const taskResult = buildTaskResult(input, verification, cfg, docsOnly);
  writeArtifact(taskResultPath(root), JSON.stringify(taskResult, null, 2) + '\n', root);
  return { taskResult, verification, events, hookOnly: hasHookOnlyEvidence(events), docsOnly, degraded };
}

export function finalResponseFormat(tr: TaskResult, filesChanged: string[] = []): string {
  return [
    `Status: ${tr.status}`,
    `What was done: ${tr.result}`,
    `Files changed: ${filesChanged.length ? filesChanged.join(', ') : '(none recorded)'}`,
    `Verification: ${tr.verification}`,
    'Risks: (state any; "none" if none)',
    `Recommended next step: ${tr.nextStep}`,
  ].join('\n');
}
