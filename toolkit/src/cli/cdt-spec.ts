#!/usr/bin/env node
// cdt-spec <files...>
// Deterministic requirement/spec extraction into the current project's .claude/specs/.

import { runSpec } from '../spec/run.js';
import { loadConfig } from '../utils/config.js';
import { info, warn } from '../utils/log.js';
import { projectRoot } from '../utils/paths.js';

async function main(): Promise<void> {
  const files = process.argv.slice(2).filter((a) => !a.startsWith('-'));
  if (files.length === 0) {
    process.stderr.write('usage: cdt-spec <files...>\n');
    process.exit(2);
  }
  const root = projectRoot();
  const cfg = loadConfig(root);
  const r = await runSpec(files, cfg, root);
  for (const w of r.warnings) warn(w);
  info(`wrote ${r.written.length} spec artifacts (${r.requirementCount} requirements) to .claude/specs/`);
  process.stdout.write(JSON.stringify({ ok: true, written: r.written, requirementCount: r.requirementCount, sensitive: r.sensitive }, null, 2) + '\n');
}

main().catch((e: unknown) => {
  process.stderr.write(`cdt-spec error: ${String(e)}\n`);
  process.exit(1);
});
