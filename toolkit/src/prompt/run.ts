// cdt-prompt orchestration: enhance → write the three artifacts (only on change) → build the capped,
// redacted additionalContext suggestion for the hook.

import { join } from 'node:path';
import { writeArtifact } from '../utils/io.js';
import { claudeDir, projectRoot } from '../utils/paths.js';
import type { CdtConfig } from '../utils/types.js';
import { redact } from '../validators/redact.js';
import { writeRedacted } from '../writers/safe-write.js';
import { renderNextPrompt, renderTaskBrief } from './brief.js';
import { enhancePrompt, type EnhanceResult } from './enhance.js';

export interface PromptRunResult {
  result: EnhanceResult;
  additionalContext: string;
  written: { brief: boolean; routing: boolean; nextPrompt: boolean };
}

export function buildAdditionalContext(r: EnhanceResult, cfg: CdtConfig): string {
  const rt = r.routing;
  const parts: string[] = [
    `CDT routing (advisory, local): tier ${rt.tier}, model ${rt.model}, confidence ${rt.confidence}` +
      (rt.risk.flagged ? `, risk: ${rt.risk.domains.join('/')} (security-review: ${rt.securityReview ? 'yes' : 'no'})` : ''),
  ];
  if (rt.agents.length > 0) parts.push('Suggested agents: ' + rt.agents.map((a) => a.name).join(', '));
  if (r.enhancedText.trim()) parts.push('\nSuggested prompt (review, do not auto-submit):\n' + r.enhancedText.trim());

  let ctx = parts.join('\n');
  const cap = cfg.prompt.maxContextChars;
  if (ctx.length > cap) ctx = ctx.slice(0, Math.max(0, cap - 16)) + '\n…(truncated)';
  return cfg.redact ? redact(ctx) : ctx;
}

export async function runPrompt(prompt: string, cfg: CdtConfig, root: string = projectRoot()): Promise<PromptRunResult> {
  const result = await enhancePrompt(prompt, cfg, root);
  const cdir = claudeDir(root);
  const routingWrite = writeArtifact(join(cdir, 'ROUTING.json'), JSON.stringify(result.routing, null, 2) + '\n', root);
  const briefWrite = writeRedacted(join(cdir, 'TASK_BRIEF.md'), renderTaskBrief(result), cfg, root);
  const nextWrite = writeRedacted(join(cdir, 'NEXT_PROMPT.md'), renderNextPrompt(result), cfg, root);
  return {
    result,
    additionalContext: buildAdditionalContext(result, cfg),
    written: { brief: briefWrite.written, routing: routingWrite.written, nextPrompt: nextWrite.written },
  };
}
