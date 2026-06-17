// Optional LOCAL Ollama backend (no external calls). Bounded by a Node AbortController timeout.

import type { CdtConfig } from '../utils/types.js';
import { buildEnhanceUserPrompt } from './prompt-builder.js';

export interface EnhanceCall {
  ok: boolean;
  text: string;
  reason: string;
}

export async function ollamaEnhance(prompt: string, cfg: CdtConfig): Promise<EnhanceCall> {
  const ctrl = new AbortController();
  const timer = setTimeout(() => ctrl.abort(), cfg.prompt.timeoutMs);
  try {
    const res = await fetch('http://localhost:11434/api/generate', {
      method: 'POST',
      signal: ctrl.signal,
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify({ model: cfg.prompt.localModel, prompt: buildEnhanceUserPrompt(prompt), stream: false }),
    });
    if (!res.ok) return { ok: false, text: '', reason: `ollama http ${res.status}` };
    const data = (await res.json()) as { response?: string };
    const text = (data.response ?? '').trim();
    return text ? { ok: true, text, reason: 'ok' } : { ok: false, text: '', reason: 'empty output' };
  } catch (e) {
    return { ok: false, text: '', reason: `ollama unreachable: ${String(e)}` };
  } finally {
    clearTimeout(timer);
  }
}
