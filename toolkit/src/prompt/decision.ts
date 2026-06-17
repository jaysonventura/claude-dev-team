// The enhancement decision gate. Deterministic. Runs the sensitivity pre-gate FIRST (fail-closed): a
// sensitive or uncertain prompt is never sent to an external model. Then decides whether the configured
// model should be called at all (only for genuinely unclear / risky / spec-driven prompts in `auto`).

import type { Classification } from '../routing/classify.js';
import type { CdtConfig } from '../utils/types.js';
import { scanSensitivity } from '../validators/sensitivity.js';

export interface PromptDecision {
  enhance: boolean; // produce an enhanced/brief artifact at all
  useModel: boolean; // call the configured (possibly external) model
  sensitive: boolean;
  failClosed: boolean;
  reasons: string[];
}

export function decide(prompt: string, cfg: CdtConfig, c: Classification): PromptDecision {
  const reasons: string[] = [];

  if (!cfg.prompt.enhance || cfg.prompt.mode === 'off') {
    return { enhance: false, useModel: false, sensitive: false, failClosed: false, reasons: ['enhancement disabled'] };
  }

  const sens = scanSensitivity(prompt);
  const tooShort = prompt.trim().length < cfg.prompt.minChars;

  let useModel = false;
  if (!sens.sensitive && !tooShort) {
    if (cfg.prompt.mode === 'always') {
      useModel = true;
      reasons.push('mode=always');
    } else {
      // auto: only when the deterministic signals say the prompt is unclear / risky / spec-driven.
      const unclear = c.confidence < cfg.prompt.confidenceThreshold;
      if (unclear) reasons.push(`low confidence ${c.confidence} < ${cfg.prompt.confidenceThreshold}`);
      if (c.riskFlagged) reasons.push('risk-flagged');
      if (c.fileSpecDriven) reasons.push('file/spec-driven');
      useModel = unclear || c.riskFlagged || c.fileSpecDriven;
      if (!useModel) reasons.push('clear prompt → pass through (no model)');
    }
  }

  if (sens.sensitive) {
    useModel = false;
    reasons.push(sens.failClosed ? 'sensitivity scan failed-closed → deterministic only' : 'sensitive content → deterministic only (no external model)');
  }
  if (tooShort) {
    useModel = false;
    reasons.push(`below min length (${cfg.prompt.minChars}) → deterministic only`);
  }

  return { enhance: true, useModel, sensitive: sens.sensitive, failClosed: sens.failClosed, reasons };
}
