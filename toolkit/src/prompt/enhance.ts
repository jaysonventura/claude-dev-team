// Orchestrate the deterministic-first enhancement pipeline: classify → decide → run backend →
// build advisory routing. Pure of I/O so it is unit-testable.

import { runEnhancer } from '../llm/backend.js';
import { classify, type Classification } from '../routing/classify.js';
import { buildRouting } from '../routing/routing.js';
import { projectRoot } from '../utils/paths.js';
import type { CdtConfig, RoutingResult } from '../utils/types.js';
import { decide, type PromptDecision } from './decision.js';

export interface EnhanceResult {
  routing: RoutingResult;
  classification: Classification;
  decision: PromptDecision;
  enhancedText: string;
  enhancedByModel: boolean;
  backend: string;
  reason: string;
  degraded: boolean;
}

export async function enhancePrompt(prompt: string, cfg: CdtConfig, root: string = projectRoot()): Promise<EnhanceResult> {
  const classification = classify(prompt);
  const decision = decide(prompt, cfg, classification);
  const out = await runEnhancer(prompt, cfg, classification, decision, root);
  const routing = buildRouting(prompt, { enhanced: out.enhanced, root });
  if (out.degraded) routing.degraded = true;
  return {
    routing,
    classification,
    decision,
    enhancedText: out.text,
    enhancedByModel: out.enhanced,
    backend: out.backend,
    reason: out.reason,
    degraded: out.degraded,
  };
}
