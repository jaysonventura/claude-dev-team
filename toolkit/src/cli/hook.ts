#!/usr/bin/env node
// Hook-mode entrypoint invoked by the Bash hook shims.
//   hook.js prompt    — UserPromptSubmit: read stdin JSON, maybe enhance, print additionalContext JSON.
//   hook.js finalize  — Stop: write TASK_RESULT.json, print a JSON summary for the Bash hook.
// ALWAYS exits 0 (fail-open) and NEVER exits 2 — exit 2 on UserPromptSubmit would erase the user's prompt.

import { readFileSync } from 'node:fs';
import { stagingWarnings } from '../guard/staging.js';
import { intake } from '../prompt/intake.js';
import { runPrompt } from '../prompt/run.js';
import { loadConfig } from '../utils/config.js';
import { hasProcessed, markProcessed, promptHash } from '../utils/io.js';
import { projectRoot } from '../utils/paths.js';
import { finalResponseFormat, finalizeTaskResult } from '../writers/result.js';

function readStdin(): Record<string, unknown> {
  try {
    const raw = readFileSync(0, 'utf8');
    return raw.trim() ? (JSON.parse(raw) as Record<string, unknown>) : {};
  } catch {
    return {};
  }
}

function emit(obj: unknown): void {
  process.stdout.write(JSON.stringify(obj));
}

function str(v: unknown): string {
  return typeof v === 'string' ? v : '';
}

async function promptMode(): Promise<void> {
  const input = readStdin();
  const root = projectRoot(str(input.cwd) || process.cwd());
  const cfg = loadConfig(root);

  // Defensive gates (the Bash shim also guards these).
  if (!cfg.enabled || !cfg.prompt.enhance || cfg.prompt.mode === 'off') return;
  if (process.env.CDT_IN_ENHANCER === '1') return;
  if (str(input.permission_mode) === 'plan') return;

  const ik = intake(str(input.prompt));
  if (!ik.normalized || ik.isSlashCommand || ik.isTrivial || ik.length < cfg.prompt.minChars) return;

  const hash = promptHash(ik.normalized, root);
  if (hasProcessed(hash, root)) return; // already processed this prompt — no rewrite

  const r = await runPrompt(ik.normalized, cfg, root);
  markProcessed(hash, root);

  const ctx = r.additionalContext.trim();
  if (ctx) emit({ hookSpecificOutput: { hookEventName: 'UserPromptSubmit', additionalContext: ctx } });
}

function finalizeMode(): void {
  const input = readStdin();
  const root = projectRoot(str(input.cwd) || process.cwd());
  const cfg = loadConfig(root);
  if (!cfg.enabled) {
    emit({ skipped: true });
    return;
  }
  const fin = finalizeTaskResult(cfg, root);
  emit({
    verification: fin.verification,
    status: fin.taskResult.status,
    docsOnly: fin.docsOnly,
    hookOnly: fin.hookOnly,
    degraded: fin.degraded,
    stagingWarnings: stagingWarnings(root),
    finalResponse: finalResponseFormat(fin.taskResult),
  });
}

const mode = process.argv[2];
void (async () => {
  try {
    if (mode === 'prompt') await promptMode();
    else if (mode === 'finalize') finalizeMode();
  } catch {
    // fail-open: never block the session on a toolkit error
  }
  process.exit(0);
})();
