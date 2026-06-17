// `cdt status` — report CDT state for the current project, including the staging guard and a
// dist/presets healthcheck.

import { existsSync } from 'node:fs';
import { join } from 'node:path';
import { stagingWarnings } from '../guard/staging.js';
import { loadConfig } from '../utils/config.js';
import { readJson } from '../utils/io.js';
import { claudeDir, packageRoot, presetsDir, projectRoot } from '../utils/paths.js';
import type { TaskResult } from '../utils/types.js';
import { computeVerification, readVerifyEvents } from '../verify/events.js';

export function runStatus(root: string = projectRoot()): void {
  const cdir = claudeDir(root);
  const cfg = loadConfig(root);
  const out: string[] = [];

  out.push(`CDT status — ${root}`);
  out.push(`  core CDT (CDT_ENABLED): ${cfg.enabled}  ·  toolkit (CDT_TOOLKIT_ENABLED): ${cfg.toolkitEnabled}`);
  out.push(`  prompt-enhance: ${cfg.prompt.enhance} (${cfg.prompt.mode})  ·  redact: ${cfg.redact}`);
  out.push(`  config: ${existsSync(join(cdir, 'cdt.config.json')) ? '.claude/cdt.config.json' : 'defaults (no project config)'}`);

  for (const f of ['TASK_BRIEF.md', 'ROUTING.json', 'NEXT_PROMPT.md', 'TASK_RESULT.json']) {
    out.push(`  ${existsSync(join(cdir, f)) ? '✓' : '·'} .claude/${f}`);
  }

  const events = readVerifyEvents(root);
  out.push(`  verification (from verify-events.jsonl): ${computeVerification(events)} (${events.length} event${events.length === 1 ? '' : 's'})`);

  const tr = readJson<TaskResult>(join(cdir, 'TASK_RESULT.json'));
  if (tr) out.push(`  last result: status=${tr.status} verification=${tr.verification}`);

  // Healthcheck — dist + presets present.
  const distOk = existsSync(join(packageRoot(), 'dist', 'cli', 'cdt.js'));
  const presetsOk = existsSync(presetsDir());
  if (!distOk) out.push('  ⚠ dist missing — run: cd toolkit && npm install && npm run build');
  if (!presetsOk) out.push('  ⚠ presets missing from package');

  const warnings = stagingWarnings(root);
  for (const w of warnings) out.push(`  ⚠ STAGING GUARD: ${w}`);

  process.stdout.write(out.join('\n') + '\n');
}
