// Backend selector + session circuit-breaker. Decides between Haiku (claude CLI), local Ollama, and the
// deterministic fallback. Never calls an external model when the decision gate forbids it.

import { join } from 'node:path';
import type { Classification } from '../routing/classify.js';
import { readJson, writeArtifact } from '../utils/io.js';
import { projectRoot, runtimeDir } from '../utils/paths.js';
import type { CdtConfig } from '../utils/types.js';
import { claudeEnhance } from './claudecli.js';
import { deterministicEnhance } from './fallback.js';
import { ollamaEnhance } from './ollama.js';
import type { PromptDecision } from '../prompt/decision.js';

export interface EnhanceOutcome {
  text: string;
  enhanced: boolean; // true only when an actual model produced the text
  backend: 'haiku' | 'ollama' | 'deterministic' | 'none';
  reason: string;
  degraded: boolean;
}

interface BreakerState {
  calls: number;
  consecutiveTimeouts: number;
  disabled: boolean;
}

function loadBreaker(root: string): BreakerState {
  return readJson<BreakerState>(join(runtimeDir(root), 'enhancer-state.json')) ?? { calls: 0, consecutiveTimeouts: 0, disabled: false };
}

function saveBreaker(root: string, s: BreakerState): void {
  try {
    writeArtifact(join(runtimeDir(root), 'enhancer-state.json'), JSON.stringify(s), root);
  } catch {
    /* best effort */
  }
}

export async function runEnhancer(
  prompt: string,
  cfg: CdtConfig,
  c: Classification,
  decision: PromptDecision,
  root: string = projectRoot(),
): Promise<EnhanceOutcome> {
  if (!decision.enhance) {
    return { text: '', enhanced: false, backend: 'none', reason: 'enhancement disabled', degraded: false };
  }
  if (!decision.useModel) {
    return {
      text: deterministicEnhance(prompt, c),
      enhanced: false,
      backend: 'deterministic',
      reason: decision.reasons.join('; ') || 'deterministic gate',
      degraded: decision.failClosed,
    };
  }

  if (cfg.prompt.backend === 'ollama') {
    const r = await ollamaEnhance(prompt, cfg);
    if (r.ok) return { text: r.text, enhanced: true, backend: 'ollama', reason: 'ok', degraded: false };
    return { text: deterministicEnhance(prompt, c), enhanced: false, backend: 'deterministic', reason: `ollama failed: ${r.reason}`, degraded: false };
  }

  // Default: Haiku via claude CLI, guarded by the session circuit-breaker.
  const br = loadBreaker(root);
  if (br.disabled || br.calls >= cfg.prompt.maxPerSession) {
    return { text: deterministicEnhance(prompt, c), enhanced: false, backend: 'deterministic', reason: 'circuit-breaker: enhancer disabled for session', degraded: false };
  }
  const r = claudeEnhance(prompt, cfg);
  br.calls += 1;
  if (r.ok) {
    br.consecutiveTimeouts = 0;
    saveBreaker(root, br);
    return { text: r.text, enhanced: true, backend: 'haiku', reason: 'ok', degraded: false };
  }
  if (r.timedOut) {
    br.consecutiveTimeouts += 1;
    if (br.consecutiveTimeouts >= 3) br.disabled = true;
  }
  saveBreaker(root, br);
  return { text: deterministicEnhance(prompt, c), enhanced: false, backend: 'deterministic', reason: `haiku failed: ${r.reason}`, degraded: false };
}
