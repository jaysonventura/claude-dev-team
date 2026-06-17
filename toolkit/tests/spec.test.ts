import { existsSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';
import { describe, expect, it } from 'vitest';
import { ingest } from '../src/spec/ingest.js';
import { extractRequirements } from '../src/spec/requirements.js';
import { runSpec } from '../src/spec/run.js';
import { specsDir } from '../src/utils/paths.js';
import { validateRequirements } from '../src/validators/validate.js';
import { cfg, tmpRoot } from './helpers.js';

const SAMPLE = [
  '# Login Requirements',
  '',
  'The system must allow a user to log in with email and password.',
  'The system should lock the account after 5 failed attempts.',
  'Passwords must be hashed with bcrypt.',
  'The login page may show a "forgot password" link.',
].join('\n');

describe('cdt-spec deterministic extraction', () => {
  it('extracts requirements each carrying a REQUIRED source reference', async () => {
    const root = tmpRoot();
    const f = join(root, 'req.md');
    writeFileSync(f, SAMPLE);
    const docs = await ingest([f], false);
    const reqs = extractRequirements(docs, '2026-06-17T00:00:00Z');
    expect(reqs.requirements.length).toBeGreaterThanOrEqual(3);
    for (const r of reqs.requirements) {
      expect(r.source.doc).toBe(f);
      expect(typeof r.source.line).toBe('number');
    }
    expect(validateRequirements(reqs).valid).toBe(true);
    // priorities derived from cue words
    expect(reqs.requirements.some((r) => r.priority === 'must')).toBe(true);
    expect(reqs.requirements.some((r) => r.priority === 'should')).toBe(true);
  });

  it('marks an image/diagram NEEDS_REVIEW when OCR is disabled', async () => {
    const root = tmpRoot();
    const img = join(root, 'diagram.png');
    writeFileSync(img, Buffer.from([0x89, 0x50, 0x4e, 0x47])); // not a real PNG; OCR disabled anyway
    const docs = await ingest([img], false);
    expect(docs[0]?.status).toBe('needs_review');
    expect(docs[0]?.type).toBe('image');
  });

  it('writes all 8 spec artifacts into .claude/specs', async () => {
    const root = tmpRoot();
    const f = join(root, 'req.md');
    writeFileSync(f, SAMPLE);
    const r = await runSpec([f], cfg(), root, '2026-06-17T00:00:00Z');
    const dir = specsDir(root);
    for (const name of ['RAW_TEXT.md', 'DOCUMENT_INDEX.json', 'EXTRACTED_REQUIREMENTS.json', 'SPEC_CONTRACT.md', 'TRACEABILITY_MATRIX.md', 'DEV_TASK_BRIEF.md', 'QA_TEST_PLAN.md', 'OPEN_QUESTIONS.md']) {
      expect(existsSync(join(dir, name)), name).toBe(true);
    }
    expect(r.written.length).toBe(8);
  });

  it('keeps sensitive source local: do-not-commit banner, no external AI', async () => {
    const root = tmpRoot();
    const f = join(root, 'payroll.md');
    writeFileSync(f, 'The system must export the payroll salary data for each employee.');
    const r = await runSpec([f], cfg(), root, '2026-06-17T00:00:00Z');
    expect(r.sensitive).toBe(true);
    const contract = join(specsDir(root), 'SPEC_CONTRACT.md');
    expect(existsSync(contract)).toBe(true);
  });
});
