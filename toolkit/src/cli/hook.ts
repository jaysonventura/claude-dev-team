#!/usr/bin/env node
// Hook-mode entrypoint invoked by the Bash hook shims.
//   hook.js prompt    — UserPromptSubmit: read stdin JSON, maybe enhance, print additionalContext JSON.
//   hook.js finalize  — Stop: write TASK_RESULT.json, print a JSON summary for the Bash hook.
// ALWAYS exits 0 (fail-open) and NEVER exits 2 — exit 2 on UserPromptSubmit would erase the user's prompt.

import { readFileSync } from 'node:fs';
import { relative } from 'node:path';
import { stagingWarnings } from '../guard/staging.js';
import { intake } from '../prompt/intake.js';
import { runPrompt } from '../prompt/run.js';
import { detectSpecFiles } from '../spec/detect.js';
import { runSpec } from '../spec/run.js';
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

  // Master gates (the Bash shim also guards these).
  if (!cfg.enabled || !cfg.toolkitEnabled) return;
  if (process.env.CDT_IN_ENHANCER === '1') return;
  if (str(input.permission_mode) === 'plan') return;

  const ik = intake(str(input.prompt));
  if (!ik.normalized || ik.isSlashCommand) return;

  const hash = promptHash(ik.normalized, root);
  if (hasProcessed(hash, root)) return; // already processed this prompt — no re-run/rewrite
  markProcessed(hash, root);

  const parts: string[] = [];

  // Spec auto-detect: extract requirements from referenced spec DOCUMENTS (PDF/DOCX, or requirement-named
  // MD/TXT) — source files and folders are excluded. Independent of the enhancement gates, opt-in via
  // CDT_SPEC_AUTO. Sensitive docs stay local (handled inside runSpec).
  if (cfg.spec.auto) {
    try {
      const files = detectSpecFiles(ik.normalized, root);
      if (files.length > 0) {
        const sr = await runSpec(files, cfg, root);
        const names = files.map((f) => relative(root, f) || f).join(', ');
        parts.push(
          `CDT auto-extracted requirements from ${names} → .claude/specs/ (${sr.requirementCount} requirement(s)). ` +
            'Read EXTRACTED_REQUIREMENTS.json + OPEN_QUESTIONS.md and resolve any NEEDS_REVIEW before implementing.',
        );
      }
    } catch {
      /* fail-open — never block the prompt */
    }
  }

  // Conditional prompt enhancement (gated: enabled, non-trivial, long enough; sensitive/uncertain handled
  // inside the decision gate).
  if (cfg.prompt.enhance && cfg.prompt.mode !== 'off' && !ik.isTrivial && ik.length >= cfg.prompt.minChars) {
    const r = await runPrompt(ik.normalized, cfg, root);
    const ctx = r.additionalContext.trim();
    if (ctx) parts.push(ctx);
  }

  if (parts.length > 0) {
    emit({ hookSpecificOutput: { hookEventName: 'UserPromptSubmit', additionalContext: parts.join('\n\n') } });
  }
}

function finalizeMode(): void {
  const input = readStdin();
  const root = projectRoot(str(input.cwd) || process.cwd());
  const cfg = loadConfig(root);
  if (!cfg.enabled || !cfg.toolkitEnabled) {
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
