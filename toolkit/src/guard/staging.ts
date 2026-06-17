// Staging guard: warn loudly (non-blocking) when a sensitivity-flagged or do-not-commit spec artifact is
// staged for commit. Used by `cdt status` and the Stop hook.

import { join } from 'node:path';
import { stagedPaths } from '../utils/git.js';
import { readText } from '../utils/io.js';
import { projectRoot } from '../utils/paths.js';

const BANNER_RE = /do[-\s]?not[-\s]?commit|sensitivity[-\s]?flag|⚠\s*sensitive/i;

export function stagingWarnings(root: string = projectRoot()): string[] {
  const warnings: string[] = [];
  for (const f of stagedPaths(root)) {
    if (!f.includes('.claude/specs/')) continue;
    const content = readText(join(root, f)) ?? '';
    if (BANNER_RE.test(content)) {
      warnings.push(`staged sensitive spec artifact carries a do-not-commit banner: ${f}`);
    }
  }
  return warnings;
}
