import { mkdirSync, symlinkSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';
import { describe, expect, it } from 'vitest';
import { appendJsonl, hasProcessed, markProcessed, promptHash, readJsonl, writeArtifact } from '../src/utils/io.js';
import { claudeDir } from '../src/utils/paths.js';
import { tmpRoot } from './helpers.js';

describe('write-jail', () => {
  it('writes inside .claude', () => {
    const root = tmpRoot();
    const r = writeArtifact(join(claudeDir(root), 'x.md'), 'hello', root);
    expect(r.written).toBe(true);
  });

  it('rejects a .. traversal escape', () => {
    const root = tmpRoot();
    mkdirSync(claudeDir(root), { recursive: true });
    expect(() => writeArtifact(join(claudeDir(root), '..', 'escape.md'), 'x', root)).toThrow(/jail/);
  });

  it('rejects a symlink escape', () => {
    const root = tmpRoot();
    mkdirSync(claudeDir(root), { recursive: true });
    symlinkSync('/tmp', join(claudeDir(root), 'link'));
    expect(() => writeArtifact(join(claudeDir(root), 'link', 'escape.md'), 'x', root)).toThrow(/jail/);
  });
});

describe('content-hash skip', () => {
  it('does not rewrite identical content', () => {
    const root = tmpRoot();
    const p = join(claudeDir(root), 'a.md');
    expect(writeArtifact(p, 'same', root).written).toBe(true);
    expect(writeArtifact(p, 'same', root).written).toBe(false);
    expect(writeArtifact(p, 'changed', root).written).toBe(true);
  });
});

describe('HMAC prompt-hash dedupe', () => {
  it('is a stable 64-hex HMAC and dedupes', () => {
    const root = tmpRoot();
    const h1 = promptHash('do the thing', root);
    const h2 = promptHash('do the thing', root);
    expect(h1).toBe(h2);
    expect(h1).toMatch(/^[a-f0-9]{64}$/);
    expect(hasProcessed(h1, root)).toBe(false);
    markProcessed(h1, root);
    expect(hasProcessed(h1, root)).toBe(true);
  });

  it('differs across project salts', () => {
    expect(promptHash('same prompt', tmpRoot())).not.toBe(promptHash('same prompt', tmpRoot()));
  });
});

describe('concurrency-safe jsonl append', () => {
  it('appends and reads back lines', () => {
    const root = tmpRoot();
    const p = join(claudeDir(root), 'runtime', 'log.jsonl');
    appendJsonl(p, { a: 1 }, root);
    appendJsonl(p, { a: 2 }, root);
    expect(readJsonl<{ a: number }>(p).map((x) => x.a)).toEqual([1, 2]);
  });
});

describe('atomic write does not produce partial files via writeFileSync race', () => {
  it('keeps prior content if same', () => {
    const root = tmpRoot();
    mkdirSync(claudeDir(root), { recursive: true });
    writeFileSync(join(claudeDir(root), 'pre.md'), 'pre');
    expect(writeArtifact(join(claudeDir(root), 'pre.md'), 'pre', root).written).toBe(false);
  });
});
