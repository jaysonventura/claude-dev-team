#!/usr/bin/env node
// cdt-prompt "<prompt>"
// Intake → routing → conditional local enhancement → write TASK_BRIEF.md, ROUTING.json, NEXT_PROMPT.md
// into the current project's .claude/.

import { runPrompt } from '../prompt/run.js';
import { loadConfig } from '../utils/config.js';
import { info, warn } from '../utils/log.js';
import { projectRoot } from '../utils/paths.js';

async function main(): Promise<void> {
  const prompt = process.argv.slice(2).filter((a) => !a.startsWith('-')).join(' ').trim();
  if (!prompt) {
    process.stderr.write('usage: cdt-prompt "<prompt>"\n');
    process.exit(2);
  }
  const root = projectRoot();
  const cfg = loadConfig(root);
  if (!cfg.enabled) {
    warn('CDT disabled (CDT_ENABLED=false) — nothing written.');
    process.exit(0);
  }
  const r = await runPrompt(prompt, cfg, root);
  const rt = r.result.routing;
  info(`tier=${rt.tier} model=${rt.model} risk=${rt.risk.flagged} securityReview=${rt.securityReview} enhanced=${r.result.enhancedByModel} backend=${r.result.backend}`);
  process.stdout.write(
    JSON.stringify(
      {
        ok: true,
        written: r.written,
        routing: { tier: rt.tier, model: rt.model, riskFlagged: rt.risk.flagged, securityReview: rt.securityReview, enhanced: r.result.enhancedByModel, confidence: rt.confidence },
      },
      null,
      2,
    ) + '\n',
  );
}

main().catch((e: unknown) => {
  process.stderr.write(`cdt-prompt error: ${String(e)}\n`);
  process.exit(1);
});
