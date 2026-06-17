// Deterministic classifier: tier (T0–T3), model floor (haiku/sonnet/opus), risk flags, security-review
// requirement, and a heuristic confidence score. RISK forces a T2+ floor + security-reviewer but does
// NOT auto-route Opus — only OPUS_ESCALATION terms do.

import type { ModelTier, SafetyFinding, Tier } from '../utils/types.js';
import { scanSafety } from '../validators/safety.js';
import { FILE_SPEC_MARKERS, hasAny, lc, OPUS_ESCALATION, TRIVIAL, VAGUE_MARKERS } from './keywords.js';

export interface Classification {
  tier: Tier;
  model: ModelTier;
  confidence: number;
  riskFlagged: boolean;
  riskDomains: string[];
  securityReview: boolean;
  fileSpecDriven: boolean;
  findings: SafetyFinding[];
  reasons: string[];
}

const SECURITY_REVIEW_DOMAINS = new Set(['auth', 'payment', 'secrets', 'permissions', 'user-data', 'migration']);

function maxTier(a: Tier, b: Tier): Tier {
  const order: Tier[] = ['T0', 'T1', 'T2', 'T3'];
  return order.indexOf(a) >= order.indexOf(b) ? a : b;
}

export function classify(prompt: string): Classification {
  const reasons: string[] = [];
  const hay = lc(prompt);
  const findings = scanSafety(prompt);
  const riskDomains = findings.map((f) => f.domain);
  const riskFlagged = findings.length > 0;
  const trivial = hasAny(hay, TRIVIAL);
  const opus = hasAny(hay, OPUS_ESCALATION);
  const fileSpecDriven = hasAny(hay, FILE_SPEC_MARKERS);
  const securityReview = riskFlagged && findings.some((f) => SECURITY_REVIEW_DOMAINS.has(f.domain));

  // Base tier from breadth/complexity.
  let tier: Tier = 'T1';
  if (trivial && !riskFlagged && !opus) {
    tier = 'T0';
    reasons.push('trivial mechanical op');
  } else if (opus || riskDomains.length >= 3) {
    tier = 'T3';
    reasons.push('architecture/cross-cutting or many risk domains');
  } else if (riskDomains.length >= 1) {
    tier = 'T2';
    reasons.push('risk domain present');
  }
  // Risk floor: never below T2 when flagged.
  if (riskFlagged) {
    tier = maxTier(tier, 'T2');
    reasons.push('RISK floor → T2+');
  }

  // Model floor.
  let model: ModelTier;
  if (opus) {
    model = 'opus';
    reasons.push('Opus escalation term');
  } else if (trivial && !riskFlagged) {
    model = 'haiku';
    reasons.push('trivial → haiku');
  } else if (riskFlagged) {
    model = 'sonnet';
    reasons.push('risk → Sonnet + security-reviewer (not Opus)');
  } else {
    model = 'sonnet';
    reasons.push('substantive build → Sonnet');
  }

  // Heuristic confidence (NOT a probability): clarity of the request.
  let confidence = 0.9;
  if (prompt.trim().length < 40) confidence -= 0.25;
  if (hasAny(hay, VAGUE_MARKERS)) confidence -= 0.25;
  if (/\?\s*$/.test(prompt.trim())) confidence -= 0.1;
  if (!/[a-z]{3,}\s+[a-z]{3,}/i.test(prompt)) confidence -= 0.15;
  if (fileSpecDriven) confidence -= 0.1; // file/spec-driven prompts benefit from a brief
  confidence = Math.max(0, Math.min(1, Number(confidence.toFixed(2))));

  return { tier, model, confidence, riskFlagged, riskDomains, securityReview, fileSpecDriven, findings, reasons };
}
