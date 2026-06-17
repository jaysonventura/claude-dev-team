// Best-effort git helpers (read-only). All fail-soft: no git / not a repo => empty lists.

import { spawnSync } from 'node:child_process';

function lines(out: string | null | undefined): string[] {
  if (!out) return [];
  return out.split('\n').map((l) => l.trim()).filter(Boolean);
}

export function editedPaths(root: string): string[] {
  const set = new Set<string>();
  const tracked = spawnSync('git', ['-C', root, 'diff', '--name-only', 'HEAD'], { encoding: 'utf8' });
  if (tracked.status === 0) for (const l of lines(tracked.stdout)) set.add(l);
  const untracked = spawnSync('git', ['-C', root, 'ls-files', '--others', '--exclude-standard'], { encoding: 'utf8' });
  if (untracked.status === 0) for (const l of lines(untracked.stdout)) set.add(l);
  return [...set];
}

export function stagedPaths(root: string): string[] {
  const res = spawnSync('git', ['-C', root, 'diff', '--cached', '--name-only'], { encoding: 'utf8' });
  if (res.status !== 0) return [];
  return lines(res.stdout);
}
