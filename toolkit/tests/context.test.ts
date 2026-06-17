import { describe, expect, it } from 'vitest';
import { buildRouting } from '../src/routing/routing.js';
import { classify } from '../src/routing/classify.js';
import { buildAdditionalContext } from '../src/prompt/run.js';
import type { EnhanceResult } from '../src/prompt/enhance.js';
import { decide } from '../src/prompt/decision.js';
import { cfg, tmpRoot } from './helpers.js';

function fakeResult(root: string, enhancedText: string): EnhanceResult {
  const prompt = 'add a payment endpoint';
  const c = classify(prompt);
  return {
    routing: buildRouting(prompt, { root, now: '2026-06-17T00:00:00Z' }),
    classification: c,
    decision: decide(prompt, cfg(), c),
    enhancedText,
    enhancedByModel: false,
    backend: 'deterministic',
    reason: 'test',
    degraded: false,
  };
}

describe('additionalContext', () => {
  it('caps length at CDT_MAX_CONTEXT_CHARS', () => {
    const root = tmpRoot();
    const longText = 'x'.repeat(10000);
    const ctx = buildAdditionalContext(fakeResult(root, longText), cfg({ maxContextChars: 500 }));
    expect(ctx.length).toBeLessThanOrEqual(500);
    expect(ctx).toContain('truncated');
  });

  it('redacts secrets in the injected context', () => {
    const root = tmpRoot();
    const ctx = buildAdditionalContext(fakeResult(root, 'use password=hunter2zzz here'), cfg());
    expect(ctx).not.toContain('hunter2zzz');
  });
});
