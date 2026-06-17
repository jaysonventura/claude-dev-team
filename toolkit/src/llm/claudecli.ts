// Haiku-via-`claude`-CLI enhancer. Uses the existing Claude Code login (no API key). Hardened:
//   --tools ""                disable all built-in tools
//   --disallowedTools mcp__*  defensively deny MCP tools
//   --no-session-persistence  do not persist a session
//   --max-budget-usd          hard cost ceiling
//   CDT_IN_ENHANCER=1         recursion guard for our own UserPromptSubmit/SessionStart hooks
// NOTE: `--bare` is deliberately NOT used — it skips credential loading too ("Not logged in"); recursion is
// prevented by the CDT_IN_ENHANCER guard instead. Timeout is enforced by Node (spawnSync `timeout`), NOT the
// shell `timeout` binary (absent on macOS).

import { spawnSync } from 'node:child_process';
import type { CdtConfig } from '../utils/types.js';
import { buildEnhanceUserPrompt, ENHANCE_SYSTEM } from './prompt-builder.js';

export interface EnhanceCall {
  ok: boolean;
  text: string;
  reason: string;
  timedOut: boolean;
}

export function claudeEnhance(prompt: string, cfg: CdtConfig, claudeBin = 'claude'): EnhanceCall {
  // NOTE: `--bare` is intentionally NOT used — it skips credential loading too ("Not logged in").
  // Recursion is prevented by CDT_IN_ENHANCER=1 (set below + checked by the UserPromptSubmit/SessionStart
  // hooks), not by --bare.
  const args = [
    '-p',
    '--no-session-persistence',
    '--model', cfg.prompt.model,
    '--tools', '',
    '--disallowedTools', 'mcp__*',
    '--output-format', 'text',
    '--append-system-prompt', ENHANCE_SYSTEM,
    '--max-budget-usd', String(cfg.prompt.maxUsd),
    buildEnhanceUserPrompt(prompt),
  ];

  const res = spawnSync(claudeBin, args, {
    encoding: 'utf8',
    timeout: cfg.prompt.timeoutMs,
    killSignal: 'SIGKILL',
    maxBuffer: 1024 * 1024,
    env: { ...process.env, CDT_IN_ENHANCER: '1' },
  });

  const timedOut = (res as { signal?: string }).signal === 'SIGKILL' || res.error?.message?.includes('ETIMEDOUT') === true;
  if (res.error) {
    return { ok: false, text: '', reason: `spawn error: ${res.error.message}`, timedOut };
  }
  if (res.status !== 0) {
    return { ok: false, text: '', reason: `exit ${res.status}: ${(res.stderr ?? '').toString().slice(0, 200)}`, timedOut };
  }
  const text = (res.stdout ?? '').toString().trim();
  if (!text) return { ok: false, text: '', reason: 'empty output', timedOut };
  return { ok: true, text, reason: 'ok', timedOut: false };
}
