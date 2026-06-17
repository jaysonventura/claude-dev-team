// cdt-spec orchestration: ingest → index → requirements → contract/traceability/dev/qa/open-questions.
// Deterministic-first. External AI is never used here (would require CDT_EXTERNAL_AI_ALLOWED + approval +
// sensitivity clearance); sensitive docs stay local and get a do-not-commit banner.

import { join } from 'node:path';
import { writeArtifact } from '../utils/io.js';
import { ensureDir, projectRoot, specsDir } from '../utils/paths.js';
import type { CdtConfig } from '../utils/types.js';
import { redact } from '../validators/redact.js';
import { validateDocumentIndex, validateRequirements } from '../validators/validate.js';
import { writeRedacted } from '../writers/safe-write.js';
import { ingest } from './ingest.js';
import {
  anySensitive,
  buildDocumentIndex,
  buildRawText,
  renderContract,
  renderDevBrief,
  renderOpenQuestions,
  renderQaPlan,
  renderTraceability,
} from './render.js';
import { extractRequirements } from './requirements.js';
import type { RequirementsDoc } from './types.js';

export interface SpecRunResult {
  written: string[];
  sensitive: boolean;
  warnings: string[];
  requirementCount: number;
  degraded: boolean;
}

export async function runSpec(
  paths: string[],
  cfg: CdtConfig,
  root: string = projectRoot(),
  nowIso: string = new Date().toISOString(),
): Promise<SpecRunResult> {
  const warnings: string[] = [];
  const dir = ensureDir(specsDir(root));
  const docs = await ingest(paths, cfg.spec.ocrEnabled);
  const reqs = extractRequirements(docs, nowIso);

  const reqOutcome = validateRequirements(reqs);
  const idxObj = buildDocumentIndex(docs);
  const idxOutcome = validateDocumentIndex(idxObj);
  const degraded = (!reqOutcome.valid && !reqOutcome.degraded) || (!idxOutcome.valid && !idxOutcome.degraded);
  if (!reqOutcome.valid) warnings.push(`EXTRACTED_REQUIREMENTS schema: ${reqOutcome.errors.slice(0, 2).join('; ')}`);
  if (!idxOutcome.valid) warnings.push(`DOCUMENT_INDEX schema: ${idxOutcome.errors.slice(0, 2).join('; ')}`);

  // Redact requirement text field-wise so the JSON stays valid.
  const reqsForWrite: RequirementsDoc = {
    ...reqs,
    requirements: reqs.requirements.map((r) => ({ ...r, text: cfg.redact ? redact(r.text) : r.text })),
  };

  const written: string[] = [];
  const writeMd = (name: string, content: string): void => {
    writeRedacted(join(dir, name), content, cfg, root);
    written.push(`specs/${name}`);
  };
  const writeJson = (name: string, obj: unknown): void => {
    writeArtifact(join(dir, name), JSON.stringify(obj, null, 2) + '\n', root);
    written.push(`specs/${name}`);
  };

  writeMd('RAW_TEXT.md', buildRawText(docs));
  writeJson('DOCUMENT_INDEX.json', idxObj);
  writeJson('EXTRACTED_REQUIREMENTS.json', reqsForWrite);
  writeMd('SPEC_CONTRACT.md', renderContract(docs, reqs));
  writeMd('TRACEABILITY_MATRIX.md', renderTraceability(docs, reqs));
  writeMd('DEV_TASK_BRIEF.md', renderDevBrief(docs, reqs));
  writeMd('QA_TEST_PLAN.md', renderQaPlan(docs, reqs));
  writeMd('OPEN_QUESTIONS.md', renderOpenQuestions(docs, reqs));

  const sensitive = anySensitive(docs);
  if (sensitive) warnings.push('sensitive source detected → spec artifacts carry a do-not-commit banner and were NOT sent to external AI');
  for (const d of docs) {
    if (d.status === 'needs_review') warnings.push(`NEEDS_REVIEW: ${d.path} (${d.note ?? 'low confidence'})`);
  }

  return { written, sensitive, warnings, requirementCount: reqs.requirements.length, degraded };
}
