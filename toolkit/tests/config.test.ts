import { mkdtempSync, readFileSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { describe, expect, it } from 'vitest';
import { loadConfig, readGlobalEnvFile, setGlobalEnv } from '../src/utils/config.js';
import { claudeDir, ensureDir } from '../src/utils/paths.js';
import { tmpRoot } from './helpers.js';

function tmpEnvFile(content: string): string {
  const f = join(mkdtempSync(join(tmpdir(), 'cdt-env-')), 'claude-dev-team.env');
  writeFileSync(f, content);
  return f;
}

describe('global env file layer', () => {
  it('reads CDT_ keys from the env file', () => {
    const env = readGlobalEnvFile({ CDT_ENV_FILE: tmpEnvFile('CDT_ENABLED=0\nCDT_PROMPT_ENHANCE_MODE=always\n') });
    expect(env.CDT_ENABLED).toBe('0');
    expect(env.CDT_PROMPT_ENHANCE_MODE).toBe('always');
  });

  it('precedence: global env file < project config < process env', () => {
    const root = tmpRoot();
    const f = tmpEnvFile('CDT_ENABLED=0\nCDT_PROMPT_ENHANCE_MODE=always\n');

    // global file applies
    let cfg = loadConfig(root, { CDT_ENV_FILE: f });
    expect(cfg.enabled).toBe(false);
    expect(cfg.prompt.mode).toBe('always');

    // project config overrides the global file
    ensureDir(claudeDir(root));
    writeFileSync(join(claudeDir(root), 'cdt.config.json'), JSON.stringify({ prompt: { mode: 'off' } }));
    cfg = loadConfig(root, { CDT_ENV_FILE: f });
    expect(cfg.prompt.mode).toBe('off');
    expect(cfg.enabled).toBe(false); // still from global file

    // process env overrides everything
    cfg = loadConfig(root, { CDT_ENV_FILE: f, CDT_PROMPT_ENHANCE_MODE: 'auto' });
    expect(cfg.prompt.mode).toBe('auto');
  });

  it('setGlobalEnv upserts one key and preserves the rest', () => {
    const f = tmpEnvFile('CDT_ENABLED=1\nCDT_REDACT=true\n');
    setGlobalEnv('CDT_ENABLED', '0', { CDT_ENV_FILE: f });
    const txt = readFileSync(f, 'utf8');
    expect(txt).toMatch(/CDT_ENABLED=0/);
    expect(txt).not.toMatch(/CDT_ENABLED=1/);
    expect(txt).toMatch(/CDT_REDACT=true/);
  });
});
