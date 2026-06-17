import { describe, expect, it } from 'vitest';
import { classify } from '../src/routing/classify.js';
import { buildRouting } from '../src/routing/routing.js';
import { tmpRoot } from './helpers.js';

describe('classifier', () => {
  it('routes "fix login bug" to T2+, sonnet + security-reviewer, NOT opus', () => {
    const c = classify('fix login bug');
    expect(c.riskFlagged).toBe(true);
    expect(c.riskDomains).toContain('auth');
    expect(['T2', 'T3']).toContain(c.tier);
    expect(c.model).toBe('sonnet');
    expect(c.securityReview).toBe(true);
  });

  it('escalates "redesign the auth architecture" to opus', () => {
    const c = classify('redesign the auth architecture for the whole platform');
    expect(c.model).toBe('opus');
  });

  it('routes a trivial mechanical op to haiku/T0', () => {
    const c = classify('rename the variable foo to bar');
    expect(c.model).toBe('haiku');
    expect(c.tier).toBe('T0');
  });

  it('does NOT flag "design token" as auth risk (negative context)', () => {
    const c = classify('add a new design token for spacing in the css system');
    expect(c.riskDomains).not.toContain('auth');
    expect(c.riskDomains).not.toContain('secrets');
  });
});

describe('buildRouting', () => {
  it('stores a redacted prompt + hash and never the raw secret', () => {
    const root = tmpRoot();
    const rt = buildRouting('connect using password=SuperSecret123 to prod', { root, now: '2026-06-17T00:00:00Z' });
    expect(rt.advisory).toBe(true);
    expect(rt.promptHash).toMatch(/^[a-f0-9]{64}$/);
    expect(rt.promptRedacted).not.toContain('SuperSecret123');
    expect(JSON.stringify(rt)).not.toContain('SuperSecret123');
  });

  it('is schema-valid (degraded:false)', () => {
    const root = tmpRoot();
    const rt = buildRouting('add a payment endpoint with stripe', { root });
    expect(rt.degraded).toBe(false);
    expect(rt.risk.flagged).toBe(true);
  });
});
