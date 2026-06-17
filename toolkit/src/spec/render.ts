// Render the deterministic spec artifacts (RAW_TEXT, DOCUMENT_INDEX, and the markdown outputs) from the
// ingested docs + extracted requirements. No content is regenerated — requirements are copied + cited.

import type { IngestedDoc, Requirement, RequirementsDoc } from './types.js';

export const DO_NOT_COMMIT_BANNER =
  '> ⚠ **DO-NOT-COMMIT — SENSITIVE**: this artifact was derived from a sensitivity-flagged source. Do not\n' +
  '> commit it; it was not sent to any external AI. Review before sharing.\n';

export function anySensitive(docs: IngestedDoc[]): boolean {
  return docs.some((d) => d.sensitivity.length > 0);
}

function banner(docs: IngestedDoc[]): string {
  return anySensitive(docs) ? DO_NOT_COMMIT_BANNER + '\n' : '';
}

export function buildRawText(docs: IngestedDoc[]): string {
  const out: string[] = ['# RAW TEXT', ''];
  docs.forEach((d, i) => {
    out.push(`<a id="doc-${i + 1}"></a>`);
    out.push(`## [doc-${i + 1}] ${d.path} (${d.type}${d.status === 'needs_review' ? ', NEEDS_REVIEW' : ''})`);
    if (d.note) out.push(`_${d.note}_`);
    out.push('');
    out.push('```');
    out.push(d.text.length ? d.text : '(no extractable text)');
    out.push('```');
    out.push('');
  });
  return out.join('\n');
}

export function buildDocumentIndex(docs: IngestedDoc[]): unknown {
  return {
    documents: docs.map((d, i) => ({
      path: d.path,
      type: d.type,
      chars: d.text.length,
      pages: d.pages,
      sections: d.sections,
      rawTextAnchor: `RAW_TEXT.md#doc-${i + 1}`,
      sensitivity: d.sensitivity,
      ocrConfidence: d.ocrConfidence,
    })),
  };
}

function cite(r: Requirement): string {
  return `${r.source.doc}:L${r.source.line ?? '?'} (${r.source.anchor ?? ''})`;
}

export function renderContract(docs: IngestedDoc[], reqs: RequirementsDoc): string {
  const must = reqs.requirements.filter((r) => r.priority === 'must');
  return [
    banner(docs) + '# Spec Contract',
    '',
    `Generated: ${reqs.generatedAt} · Source documents: ${reqs.documents.join(', ')}`,
    '',
    'Derived **deterministically**. Requirements are copied and cited, never regenerated.',
    '',
    `## Must-have requirements (${must.length})`,
    '',
    ...(must.length ? must.map((r) => `- **${r.id}** (${r.type}): ${r.text}  \n  _source: ${cite(r)}_`) : ['_none extracted_']),
    '',
    `Total requirements: ${reqs.requirements.length}. See OPEN_QUESTIONS.md for gaps.`,
    '',
  ].join('\n');
}

export function renderTraceability(docs: IngestedDoc[], reqs: RequirementsDoc): string {
  const rows = reqs.requirements.map((r) => `| ${r.id} | ${cite(r)} | (assign) | ${r.status === 'needs_review' ? 'NEEDS_REVIEW' : 'pending'} |`);
  return [
    banner(docs) + '# Traceability Matrix',
    '',
    `Generated: ${reqs.generatedAt}`,
    '',
    '| Req ID | Source (doc · location) | Planned artifact | Verification |',
    '|---|---|---|---|',
    ...(rows.length ? rows : ['| — | — | — | — |']),
    '',
  ].join('\n');
}

export function renderQaPlan(docs: IngestedDoc[], reqs: RequirementsDoc): string {
  const rows = reqs.requirements.map((r) => `| ${r.id} | ${r.text.slice(0, 80)} | (define test) | ${r.status} |`);
  return [
    banner(docs) + '# QA Test Plan',
    '',
    `Generated: ${reqs.generatedAt}`,
    '',
    'Run each verification via `cdt-verify -- <command>` to record trusted evidence.',
    '',
    '| Req ID | Requirement (cited) | Test approach | Status |',
    '|---|---|---|---|',
    ...(rows.length ? rows : ['| — | — | — | — |']),
    '',
  ].join('\n');
}

export function renderDevBrief(docs: IngestedDoc[], reqs: RequirementsDoc): string {
  const must = reqs.requirements.filter((r) => r.priority === 'must');
  const sc = reqs.requirements.filter((r) => r.priority === 'should' || r.priority === 'could');
  const risky = reqs.requirements.filter((r) => r.risk.length > 0 || r.sensitivity.length > 0);
  return [
    banner(docs) + '# Dev Task Brief',
    '',
    `Generated: ${reqs.generatedAt}`,
    '',
    'Build against the cited requirements only; do not invent scope.',
    '',
    `## Must-have (${must.length})`,
    ...(must.length ? must.map((r) => `- ${r.id}: ${r.text}`) : ['- _none_']),
    '',
    `## Should / Could (${sc.length})`,
    ...(sc.length ? sc.map((r) => `- ${r.id}: ${r.text}`) : ['- _none_']),
    '',
    `## Risk / sensitivity (${risky.length})`,
    ...(risky.length ? risky.map((r) => `- ${r.id}: risk[${r.risk.join(',')}] sensitivity[${r.sensitivity.join(',')}]`) : ['- _none flagged_']),
    '',
  ].join('\n');
}

export function renderOpenQuestions(docs: IngestedDoc[], reqs: RequirementsDoc): string {
  const items: string[] = [];
  for (const d of docs) {
    if (d.status === 'needs_review') items.push(`- NEEDS_REVIEW: \`${d.path}\` — ${d.note ?? 'could not extract reliably'}.`);
    if (d.sensitivity.length > 0) items.push(`- SENSITIVE: \`${d.path}\` flagged [${d.sensitivity.join(', ')}] — kept local, not sent to external AI.`);
  }
  for (const r of reqs.requirements) {
    if (!r.source.doc) items.push(`- ${r.id}: missing source reference.`);
    if (r.status === 'needs_review') items.push(`- ${r.id}: from a NEEDS_REVIEW source — confirm wording.`);
  }
  if (reqs.requirements.length === 0) items.push('- No requirements were extracted — confirm the documents contain requirement language ("must", "shall", "should").');
  return [
    banner(docs) + '# Open Questions',
    '',
    `Generated: ${reqs.generatedAt}`,
    '',
    'Resolve before implementation — do not guess.',
    '',
    ...(items.length ? items : ['- None.']),
    '',
  ].join('\n');
}
