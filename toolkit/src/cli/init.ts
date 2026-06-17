// `cdt init` — scaffold the project's .claude config: directories, a starter cdt.config.json, copies of
// the packaged templates/presets, and .gitignore entries for the generated ephemeral artifacts.

import { cpSync, existsSync, readFileSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';
import { DEFAULT_CONFIG } from '../utils/config.js';
import { info, warn } from '../utils/log.js';
import { claudeDir, ensureDir, presetsDir, projectRoot, templatesDir } from '../utils/paths.js';

const GITIGNORE_ENTRIES = [
  '.claude/runtime/',
  '.claude/TASK_BRIEF.md',
  '.claude/ROUTING.json',
  '.claude/NEXT_PROMPT.md',
  '.claude/TASK_RESULT.json',
];

function ensureGitignore(root: string): void {
  const gi = join(root, '.gitignore');
  if (!existsSync(gi)) {
    warn('no .gitignore found — add these manually:\n  ' + GITIGNORE_ENTRIES.join('\n  '));
    return;
  }
  const current = readFileSync(gi, 'utf8');
  const missing = GITIGNORE_ENTRIES.filter((e) => !current.split('\n').some((l) => l.trim() === e));
  if (missing.length === 0) return;
  const block = '\n# claude-dev-team-toolkit (generated, ephemeral)\n' + missing.join('\n') + '\n';
  writeFileSync(gi, current.endsWith('\n') ? current + block : current + '\n' + block, 'utf8');
  info(`added ${missing.length} entr${missing.length === 1 ? 'y' : 'ies'} to .gitignore`);
}

export function runInit(root: string = projectRoot()): void {
  const cdir = claudeDir(root);
  for (const d of ['', 'agents', 'templates', 'reports', 'specs', 'runtime']) {
    ensureDir(d ? join(cdir, d) : cdir);
  }

  const cfgPath = join(cdir, 'cdt.config.json');
  if (!existsSync(cfgPath)) {
    writeFileSync(cfgPath, JSON.stringify(DEFAULT_CONFIG, null, 2) + '\n', 'utf8');
    info('wrote .claude/cdt.config.json');
  } else {
    info('.claude/cdt.config.json already exists — left untouched');
  }

  try {
    cpSync(templatesDir(), join(cdir, 'templates'), { recursive: true });
  } catch (e) {
    warn(`could not copy templates: ${String(e)}`);
  }
  try {
    cpSync(presetsDir(), join(cdir, 'agents'), { recursive: true });
  } catch (e) {
    warn(`could not copy presets: ${String(e)}`);
  }

  ensureGitignore(root);
  info(`initialized CDT in ${cdir}`);
}
