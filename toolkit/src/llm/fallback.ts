// Deterministic, non-LLM enhancement: a structured restatement that never invents facts. Used when the
// model is disabled, sensitive, too short, unavailable, slow, or has failed.

import type { Classification } from '../routing/classify.js';

export function deterministicEnhance(prompt: string, c: Classification): string {
  const lines: string[] = [];
  lines.push(`Goal: ${prompt.trim()}`);
  lines.push('');
  lines.push('Deterministic framing (no external model was used):');
  lines.push(`- Suggested tier ${c.tier}, model ${c.model}${c.securityReview ? ' + security-reviewer' : ''} (advisory).`);
  if (c.riskFlagged) {
    lines.push(`- Risk domains: ${c.riskDomains.join(', ')}. Treat as ${c.tier}+; no destructive/production actions without explicit approval.`);
  } else {
    lines.push('- No risk domains detected by the deterministic scan.');
  }
  lines.push('- Confirm acceptance criteria and scope before implementing.');
  lines.push('- Prefer existing repo automation and approved MCP sources over guessing.');
  return lines.join('\n');
}
