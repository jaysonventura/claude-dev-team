// Render TASK_BRIEF.md and NEXT_PROMPT.md from an EnhanceResult. Both are passed through redaction by the
// writer; the brief uses the already-redacted prompt from routing.

import { mcpDirective } from '../utils/mcp.js';
import type { EnhanceResult } from './enhance.js';

export function renderTaskBrief(r: EnhanceResult): string {
  const { routing: rt, classification: c } = r;
  const agents = rt.agents.length > 0 ? rt.agents.map((a) => `- **${a.name}**${a.owns.length ? ` (owns ${a.owns.join(', ')})` : ''} — ${a.reason}`).join('\n') : '- _(none recommended)_';
  return [
    '# Task Brief',
    '',
    `Generated: ${rt.generatedAt} · Tier ${rt.tier} · Model ${rt.model} · Confidence ${rt.confidence} (heuristic) · Advisory`,
    '',
    '## Original request (redacted)',
    '',
    rt.promptRedacted,
    '',
    '## Routing (advisory — the orchestrator decides)',
    '',
    `- Risk: ${rt.risk.flagged ? `flagged (${rt.risk.domains.join(', ')}) → floor ${rt.risk.floor}` : 'none'}`,
    `- Security review required: ${rt.securityReview ? 'yes' : 'no'}`,
    `- Enhanced by model: ${r.enhancedByModel ? 'yes' : 'no'} (backend: ${r.backend})`,
    '',
    '### Recommended agents',
    agents,
    '',
    '### Quality gates',
    `- ${rt.gates.join(' → ')}`,
    '',
    '## Notes',
    '',
    rt.notes || '_none_',
    c.reasons.length ? `\n_Classifier: ${c.reasons.join('; ')}_` : '',
    '',
  ].join('\n');
}

export function renderNextPrompt(r: EnhanceResult): string {
  return [
    '# Next prompt (review before use)',
    '',
    '> This is a **suggestion** generated locally. Review and edit before submitting. Sensitive prompts are',
    '> never sent to an external model; the original prompt is never rewritten automatically.',
    '',
    '## Suggested prompt',
    '',
    r.enhancedText.trim() || '_(no enhancement — use your original prompt)_',
    '',
    '## Grounding',
    '',
    mcpDirective(),
    '',
  ].join('\n');
}
