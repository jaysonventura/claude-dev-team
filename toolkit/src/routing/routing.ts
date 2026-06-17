// Assemble the advisory ROUTING.json object: classify → recommend agents/gates → redact + hash the
// prompt (never store raw) → schema-validate (safe-degrade sets degraded:true, never throws).

import { promptHash } from '../utils/io.js';
import { projectRoot } from '../utils/paths.js';
import type { RoutingResult, Tier } from '../utils/types.js';
import { redact } from '../validators/redact.js';
import { validateRouting } from '../validators/validate.js';
import { recommendAgents, recommendGates } from './agents.js';
import { classify } from './classify.js';

export const ROUTING_VERSION = '1';

export function buildRouting(prompt: string, opts: { enhanced?: boolean; root?: string; now?: string } = {}): RoutingResult {
  const root = opts.root ?? projectRoot();
  const c = classify(prompt);
  const agents = recommendAgents(prompt, c);
  const gates = recommendGates(c);

  const floor: Tier | 'none' = c.riskFlagged ? 'T2' : 'none';
  const routing: RoutingResult = {
    version: ROUTING_VERSION,
    generatedAt: opts.now ?? new Date().toISOString(),
    promptRedacted: redact(prompt),
    promptHash: promptHash(prompt, root),
    tier: c.tier,
    model: c.model,
    confidence: c.confidence,
    advisory: true,
    enhanced: opts.enhanced ?? false,
    degraded: false,
    risk: { flagged: c.riskFlagged, domains: c.riskDomains, floor },
    securityReview: c.securityReview,
    agents,
    gates,
    safety: { findings: c.findings },
    notes: c.reasons.join('; '),
  };

  const outcome = validateRouting(routing);
  if (!outcome.valid) {
    routing.degraded = true;
    routing.notes = `${routing.notes} | routing schema degraded: ${outcome.errors.slice(0, 2).join('; ')}`;
  }
  return routing;
}
