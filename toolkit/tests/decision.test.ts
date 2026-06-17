import { describe, expect, it } from 'vitest';
import { classify } from '../src/routing/classify.js';
import { decide } from '../src/prompt/decision.js';
import { cfg } from './helpers.js';

function d(prompt: string, overrides = {}) {
  return decide(prompt, cfg(overrides), classify(prompt));
}

describe('decision gate', () => {
  it('passes a clear, well-specified prompt through WITHOUT a model call', () => {
    const r = d('Add a unit test for the formatDate helper covering leap years and timezone offsets in utils.');
    expect(r.enhance).toBe(true);
    expect(r.useModel).toBe(false);
  });

  it('calls the model for a long, vague prompt', () => {
    const r = d('please improve the dashboard somehow to make it better for people and handle the edge cases');
    expect(r.useModel).toBe(true);
  });

  it('NEVER calls the model for a sensitive prompt (fail-closed), even if long & vague', () => {
    const r = d('improve the login flow somehow; the api key is sk-ant-abc123def456ghi789jkl012mno and password=hunter2zzz');
    expect(r.sensitive).toBe(true);
    expect(r.useModel).toBe(false);
  });

  it('does not call the model for a too-short prompt', () => {
    const r = d('fix login bug');
    expect(r.useModel).toBe(false);
  });

  it('mode=off disables enhancement entirely', () => {
    const r = d('please improve the dashboard somehow to make it better for people and handle edge cases', { mode: 'off' });
    expect(r.enhance).toBe(false);
    expect(r.useModel).toBe(false);
  });
});
