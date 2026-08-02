import { describe, expect, it } from 'vitest';
import type { VerifyEvent } from '../src/utils/types.js';
import { classifyVerifyType, computeVerification, failingEvents, hasHookOnlyEvidence } from '../src/verify/events.js';
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

describe('convergence: the newest run per command decides', () => {
  const at = (ts: string, over: Partial<VerifyEvent> = {}): VerifyEvent => ev({ ts, ...over });

  it('a fix turns failed back to passed — otherwise the loop can never exit', () => {
    const evs = [at('2026-08-02T10:00:00Z', { exitCode: 1 }), at('2026-08-02T10:05:00Z', { exitCode: 0 })];
    expect(computeVerification(evs)).toBe('passed');
    expect(failingEvents(evs)).toHaveLength(0);
  });

  it('a regression turns passed back to failed', () => {
    const evs = [at('2026-08-02T10:00:00Z', { exitCode: 0 }), at('2026-08-02T10:05:00Z', { exitCode: 3 })];
    expect(computeVerification(evs)).toBe('failed');
    expect(failingEvents(evs)[0]?.exitCode).toBe(3);
  });

  it('a passing lint never masks a failing test', () => {
    const evs = [
      at('2026-08-02T10:00:00Z', { command: 'npm test', exitCode: 1 }),
      at('2026-08-02T10:05:00Z', { command: 'npm run lint', exitCode: 0 }),
    ];
    expect(computeVerification(evs)).toBe('failed');
    expect(failingEvents(evs).map((e) => e.command)).toEqual(['npm test']);
  });

  it('ties break toward append order (the later line wins)', () => {
    const evs = [at('2026-08-02T10:00:00Z', { exitCode: 1 }), at('2026-08-02T10:00:00Z', { exitCode: 0 })];
    expect(computeVerification(evs)).toBe('passed');
  });
});

describe('staleness: evidence older than the last edit is not evidence', () => {
  const EDIT = '2026-08-02T12:00:00Z';

  it('a green run from before the edit does not count as passed', () => {
    const evs = [ev({ ts: '2026-08-02T11:00:00Z', exitCode: 0 })];
    expect(computeVerification(evs)).toBe('passed'); // unscoped: the old, wrong answer
    expect(computeVerification(evs, EDIT)).toBe('not_run'); // scoped: honest
  });

  it('a green run after the edit does count', () => {
    expect(computeVerification([ev({ ts: '2026-08-02T12:30:00Z', exitCode: 0 })], EDIT)).toBe('passed');
  });

  it('a stale PASS cannot cover a fresh FAIL', () => {
    const evs = [
      ev({ ts: '2026-08-02T11:00:00Z', command: 'npm test', exitCode: 0 }),
      ev({ ts: '2026-08-02T12:30:00Z', command: 'npm test', exitCode: 1 }),
    ];
    expect(computeVerification(evs, EDIT)).toBe('failed');
  });

  it('an unparseable timestamp is excluded when a floor is set, not silently trusted', () => {
    expect(computeVerification([ev({ ts: 'now', exitCode: 0 })], EDIT)).toBe('not_run');
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
