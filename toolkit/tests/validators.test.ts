import { describe, expect, it } from 'vitest';
import { redact } from '../src/validators/redact.js';
import { scanSafety } from '../src/validators/safety.js';
import { scanSensitivity } from '../src/validators/sensitivity.js';
import { validateRequirements, validateRouting, validateTaskResult, validateVerifyEvent } from '../src/validators/validate.js';

describe('redaction', () => {
  it('masks secrets and PII so they never survive into an artifact', () => {
    const input = 'token sk-ant-abc123def456ghi789jkl012 and password=hunter2zzz email a@b.com key AKIA1234567890ABCDEF';
    const out = redact(input);
    expect(out).not.toContain('sk-ant-abc123def456ghi789jkl012');
    expect(out).not.toContain('hunter2zzz');
    expect(out).not.toContain('a@b.com');
    expect(out).not.toContain('AKIA1234567890ABCDEF');
    expect(out).toContain('‹redacted:');
  });
});

describe('safety scan', () => {
  it('flags risk domains with word boundaries', () => {
    const f = scanSafety('add an auth endpoint that takes a stripe payment');
    const domains = f.map((x) => x.domain);
    expect(domains).toContain('auth');
    expect(domains).toContain('payment');
  });
});

describe('sensitivity scan (fail-closed)', () => {
  it('flags payroll/credentials content', () => {
    expect(scanSensitivity('here is the payroll spreadsheet with salary data').sensitive).toBe(true);
    expect(scanSensitivity('production database credentials').sensitive).toBe(true);
  });
  it('does not flag ordinary prose', () => {
    expect(scanSensitivity('add a button to the navbar').sensitive).toBe(false);
  });
});

describe('schema validation', () => {
  it('rejects a requirement without a source reference', () => {
    const bad = {
      version: '1',
      generatedAt: 'now',
      documents: ['a.md'],
      requirements: [{ id: 'REQ-001', text: 'x', type: 'functional', priority: 'must', status: 'extracted' }],
    };
    expect(validateRequirements(bad).valid).toBe(false);
  });

  it('accepts a requirement with a source reference', () => {
    const good = {
      version: '1',
      generatedAt: 'now',
      documents: ['a.md'],
      requirements: [{ id: 'REQ-001', text: 'x must y', type: 'functional', priority: 'must', source: { doc: 'a.md' }, status: 'extracted' }],
    };
    expect(validateRequirements(good).valid).toBe(true);
  });

  it('validates a TASK_RESULT shape and a verify-event shape', () => {
    expect(validateTaskResult({ status: 'done', task: 't', result: 'r', verification: 'passed', artifact: null, nextStep: 'n' }).valid).toBe(true);
    expect(validateVerifyEvent({ ts: 'now', command: 'npm test', type: 'test', exitCode: 0, cwd: '/x', source: 'cdt-verify' }).valid).toBe(true);
    expect(validateVerifyEvent({ ts: 'now', command: 'x', type: 'other', exitCode: null, cwd: '/x', source: 'hook' }).valid).toBe(true);
  });

  it('safe-degrades on garbage without throwing', () => {
    expect(() => validateRouting(undefined)).not.toThrow();
    expect(validateRouting(undefined).valid).toBe(false);
  });
});
