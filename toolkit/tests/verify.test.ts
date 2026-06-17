import { describe, expect, it } from 'vitest';
import type { VerifyEvent } from '../src/utils/types.js';
import { classifyVerifyType, computeVerification, hasHookOnlyEvidence } from '../src/verify/events.js';
import { finalizeTaskResult, isDocsOnly } from '../src/writers/result.js';
import { cfg, tmpRoot } from './helpers.js';

const ev = (over: Partial<VerifyEvent>): VerifyEvent => ({
  ts: 'now',
  command: 'npm test',
  type: 'test',
  exitCode: 0,
  cwd: '/x',
  source: 'cdt-verify',
  ...over,
});

describe('verification mapping (verify-events is the only trusted source)', () => {
  it('no events => not_run', () => {
    expect(computeVerification([])).toBe('not_run');
  });
  it('cdt-verify exitCode 0 => passed', () => {
    expect(computeVerification([ev({ exitCode: 0 })])).toBe('passed');
  });
  it('cdt-verify exitCode > 0 => failed', () => {
    expect(computeVerification([ev({ exitCode: 0 }), ev({ exitCode: 2 })])).toBe('failed');
  });
  it('hook-sourced null can NEVER produce passed', () => {
    expect(computeVerification([ev({ source: 'hook', exitCode: null })])).toBe('not_run');
  });
  it('detects hook-only evidence', () => {
    expect(hasHookOnlyEvidence([ev({ source: 'hook', exitCode: null })])).toBe(true);
    expect(hasHookOnlyEvidence([ev({ source: 'cdt-verify', exitCode: 0 })])).toBe(false);
  });
});

describe('classifyVerifyType', () => {
  it('classifies common commands', () => {
    expect(classifyVerifyType('npm test')).toBe('test');
    expect(classifyVerifyType('npm run build')).toBe('build');
    expect(classifyVerifyType('eslint .')).toBe('lint');
    expect(classifyVerifyType('tsc --noEmit')).toBe('typecheck');
    expect(classifyVerifyType('echo hi')).toBe('other');
  });
});

describe('finalize never fabricates verification', () => {
  it('synthesizes not_run when no verify evidence exists', () => {
    const root = tmpRoot();
    const fin = finalizeTaskResult(cfg(), root, { editedPaths: ['src/x.ts'] });
    expect(fin.verification).toBe('not_run');
    expect(['partial', 'failed', 'done', 'blocked', 'needs_review']).toContain(fin.taskResult.status);
    expect(fin.taskResult.verification).toBe('not_run');
  });
});

describe('docs-only exemption', () => {
  it('treats plan/markdown-only edits as docs-only', () => {
    expect(isDocsOnly(['.claude/plans/p.md', 'README.md'])).toBe(true);
    expect(isDocsOnly(['src/x.ts'])).toBe(false);
    expect(isDocsOnly([])).toBe(false);
  });
});
