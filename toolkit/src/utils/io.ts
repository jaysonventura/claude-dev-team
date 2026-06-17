// I/O primitives: jail-checked atomic writes, content-hash skip, concurrency-safe JSONL append,
// HMAC prompt hashing with a project-local salt, and prompt dedupe bookkeeping.

import { createHash, createHmac, randomBytes } from 'node:crypto';
import { appendFileSync, existsSync, readFileSync, renameSync, writeFileSync } from 'node:fs';
import { basename, dirname, join } from 'node:path';
import { assertWithinJail, claudeDir, ensureDir, projectRoot, runtimeDir } from './paths.js';

export function sha256(s: string): string {
  return createHash('sha256').update(s, 'utf8').digest('hex');
}

export function hmac(s: string, key: string): string {
  return createHmac('sha256', key).update(s, 'utf8').digest('hex');
}

export function readText(path: string): string | null {
  try {
    return readFileSync(path, 'utf8');
  } catch {
    return null;
  }
}

export function readJson<T>(path: string): T | null {
  const raw = readText(path);
  if (raw === null) return null;
  try {
    return JSON.parse(raw) as T;
  } catch {
    return null;
  }
}

export interface WriteResult {
  written: boolean;
  path: string;
}

/**
 * Write `content` to a path that must resolve inside `<root>/.claude`. Skips the write when the existing
 * file already has identical content (content-hash compare). Atomic via temp-file + rename.
 */
export function writeArtifact(targetPath: string, content: string, root: string = projectRoot()): WriteResult {
  const jail = ensureDir(claudeDir(root));
  const resolved = assertWithinJail(targetPath, jail);
  const existing = readText(resolved);
  if (existing !== null && sha256(existing) === sha256(content)) {
    return { written: false, path: resolved };
  }
  ensureDir(dirname(resolved));
  const tmp = join(dirname(resolved), `.${basename(resolved)}.tmp-${process.pid}`);
  writeFileSync(tmp, content, 'utf8');
  renameSync(tmp, resolved);
  return { written: true, path: resolved };
}

/**
 * Concurrency-safe append of one JSON object as a single line. Uses O_APPEND (flag 'a'); a lone JSON
 * line is well under PIPE_BUF, so the single write() is atomic across processes.
 */
export function appendJsonl(targetPath: string, obj: unknown, root: string = projectRoot()): void {
  const jail = ensureDir(claudeDir(root));
  const resolved = assertWithinJail(targetPath, jail);
  ensureDir(dirname(resolved));
  appendFileSync(resolved, JSON.stringify(obj) + '\n', { flag: 'a', encoding: 'utf8' });
}

export function readJsonl<T>(path: string): T[] {
  const raw = readText(path);
  if (raw === null) return [];
  const out: T[] = [];
  for (const line of raw.split('\n')) {
    const t = line.trim();
    if (!t) continue;
    try {
      out.push(JSON.parse(t) as T);
    } catch {
      // skip malformed lines
    }
  }
  return out;
}

/** Project-local salt for HMAC prompt hashing. Generated once, stored 0600 under runtime/. */
export function getOrCreateSalt(root: string = projectRoot()): string {
  const dir = ensureDir(runtimeDir(root));
  const saltFile = join(dir, '.salt');
  const existing = readText(saltFile);
  if (existing && existing.trim().length >= 32) return existing.trim();
  const salt = randomBytes(32).toString('hex');
  try {
    writeFileSync(saltFile, salt, { encoding: 'utf8', mode: 0o600 });
  } catch {
    /* best effort */
  }
  return salt;
}

export function promptHash(prompt: string, root: string = projectRoot()): string {
  return hmac(prompt, getOrCreateSalt(root));
}

const PROCESSED_CAP = 200;

export function hasProcessed(hash: string, root: string = projectRoot()): boolean {
  const file = join(runtimeDir(root), 'processed-prompts.json');
  const list = readJson<string[]>(file) ?? [];
  return list.includes(hash);
}

export function markProcessed(hash: string, root: string = projectRoot()): void {
  const dir = ensureDir(runtimeDir(root));
  const file = join(dir, 'processed-prompts.json');
  const list = readJson<string[]>(file) ?? [];
  if (list.includes(hash)) return;
  list.push(hash);
  while (list.length > PROCESSED_CAP) list.shift();
  writeFileSync(file, JSON.stringify(list), 'utf8');
}
