// Filesystem location helpers + the realpath() write-jail.
//
// Project root = the current working directory (per the toolkit contract). All generated output is
// written under <projectRoot>/.claude. The write-jail rejects any target that resolves (via realpath,
// so symlinks are followed) outside that .claude directory, and rejects `..` traversal.

import { existsSync, mkdirSync, realpathSync } from 'node:fs';
import { dirname, join, resolve, sep } from 'node:path';
import { fileURLToPath } from 'node:url';

/** Root of the installed toolkit package (one level above dist/), so presets/ and templates/ resolve. */
export function packageRoot(): string {
  // This file compiles to dist/utils/paths.js -> packageRoot is two levels up.
  return resolve(dirname(fileURLToPath(import.meta.url)), '..', '..');
}

export function presetsDir(): string {
  return join(packageRoot(), 'presets');
}

export function templatesDir(): string {
  return join(packageRoot(), 'templates');
}

export function projectRoot(cwd: string = process.cwd()): string {
  return resolve(cwd);
}

export function claudeDir(root: string = projectRoot()): string {
  return join(root, '.claude');
}

export function runtimeDir(root: string = projectRoot()): string {
  return join(claudeDir(root), 'runtime');
}

export function specsDir(root: string = projectRoot()): string {
  return join(claudeDir(root), 'specs');
}

export function ensureDir(dir: string): string {
  mkdirSync(dir, { recursive: true });
  return dir;
}

/** Realpath of the nearest existing ancestor, with the non-existing tail re-appended. */
export function realpathNearest(p: string): string {
  let cur = resolve(p);
  const tail: string[] = [];
  while (!existsSync(cur)) {
    const parent = dirname(cur);
    if (parent === cur) break;
    tail.unshift(cur.slice(parent.length + 1));
    cur = parent;
  }
  const real = existsSync(cur) ? realpathSync(cur) : cur;
  return tail.length > 0 ? resolve(real, ...tail) : real;
}

/**
 * Assert `target` resolves inside `jailRoot` (which must already exist). Returns the resolved absolute
 * path. Throws on symlink escape or `..` traversal.
 */
export function assertWithinJail(target: string, jailRoot: string): string {
  const jailReal = realpathSync(jailRoot);
  const resolved = realpathNearest(target);
  if (resolved !== jailReal && !resolved.startsWith(jailReal + sep)) {
    throw new Error(`refused write outside .claude jail: ${target}`);
  }
  return resolved;
}
