import { mkdtempSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { DEFAULT_CONFIG } from '../src/utils/config.js';
import type { CdtConfig } from '../src/utils/types.js';

export function tmpRoot(): string {
  return mkdtempSync(join(tmpdir(), 'cdt-test-'));
}

export function cfg(overrides: Partial<CdtConfig['prompt']> = {}): CdtConfig {
  return {
    ...DEFAULT_CONFIG,
    prompt: { ...DEFAULT_CONFIG.prompt, ...overrides },
    spec: { ...DEFAULT_CONFIG.spec },
    verify: { ...DEFAULT_CONFIG.verify },
  };
}
