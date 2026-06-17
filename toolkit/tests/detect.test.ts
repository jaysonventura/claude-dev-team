import { mkdirSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';
import { describe, expect, it } from 'vitest';
import { detectSpecFiles } from '../src/spec/detect.js';
import { tmpRoot } from './helpers.js';

describe('detectSpecFiles — only real spec documents, never source/folders', () => {
  it('detects real PDF and DOCX documents', () => {
    const root = tmpRoot();
    writeFileSync(join(root, 'requirements.pdf'), '%PDF-1.4');
    writeFileSync(join(root, 'spec.docx'), 'x');
    const f = detectSpecFiles('implement requirements.pdf and spec.docx please', root);
    expect(f.length).toBe(2);
  });

  it('detects a requirement-named markdown but NOT a plain README', () => {
    const root = tmpRoot();
    writeFileSync(join(root, 'requirements.md'), 'the system must …');
    writeFileSync(join(root, 'README.md'), 'readme');
    const f = detectSpecFiles('build from requirements.md (see README.md)', root);
    expect(f.length).toBe(1);
    expect(f[0]?.endsWith('requirements.md')).toBe(true);
  });

  it('NEVER treats source code / config as a spec', () => {
    const root = tmpRoot();
    for (const n of ['app.ts', 'config.json', 'main.py', 'styles.css', 'schema.sql']) writeFileSync(join(root, n), 'x');
    expect(detectSpecFiles('fix app.ts, config.json, main.py, styles.css and schema.sql', root)).toEqual([]);
  });

  it('excludes a DIRECTORY even when it is named like a spec (isFile check)', () => {
    const root = tmpRoot();
    mkdirSync(join(root, 'requirements.pdf'), { recursive: true }); // a folder named like a pdf
    expect(detectSpecFiles('process the requirements.pdf folder', root)).toEqual([]);
  });

  it('ignores non-existent paths and bare URLs', () => {
    const root = tmpRoot();
    expect(detectSpecFiles('see missing.pdf and https://example.com/spec.pdf', root)).toEqual([]);
  });
});
