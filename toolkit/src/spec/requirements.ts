// Deterministic requirement extraction: copy-and-cite, never regenerate. Each requirement carries a
// REQUIRED source reference (doc + line + RAW_TEXT anchor) and is tagged with risk + sensitivity.

import { scanSafety } from '../validators/safety.js';
import { scanSensitivity } from '../validators/sensitivity.js';
import type { IngestedDoc, Requirement, RequirementsDoc } from './types.js';

const REQ_VERSION = '1';
const MAX_REQUIREMENTS = 300;
const CUE = /\b(must not|must|shall not|shall|should not|should|required|will|needs to|is expected to|the system)\b/i;

function priorityOf(line: string): Requirement['priority'] {
  const l = line.toLowerCase();
  if (/\bwon'?t\b|\bwill not\b|\bout of scope\b/.test(l)) return 'wont';
  if (/\bmust not\b|\bshall not\b|\bmust\b|\bshall\b|\brequired\b/.test(l)) return 'must';
  if (/\bshould\b/.test(l)) return 'should';
  if (/\bmay\b|\bcould\b|\boptional\b/.test(l)) return 'could';
  return 'should';
}

function typeOf(line: string): Requirement['type'] {
  const l = line.toLowerCase();
  if (/\bassume\b|\bassumption\b/.test(l)) return 'assumption';
  if (/performance|latency|scalab|availab|security|throughput|uptime|response time/.test(l)) return 'nonfunctional';
  if (/must not|shall not|\bonly\b|\blimit\b|no more than|at most|\bconstraint\b/.test(l)) return 'constraint';
  return 'functional';
}

export function extractRequirements(docs: IngestedDoc[], nowIso: string): RequirementsDoc {
  const requirements: Requirement[] = [];
  let n = 0;
  docs.forEach((doc, di) => {
    if (!doc.text.trim()) return;
    const lines = doc.text.split('\n');
    for (let li = 0; li < lines.length; li += 1) {
      if (n >= MAX_REQUIREMENTS) break;
      const line = (lines[li] ?? '').trim();
      if (line.length < 15 || !CUE.test(line)) continue;
      const text = line.replace(/^([-*•\d.)\s]+)/, '').trim();
      if (text.length < 12) continue;
      n += 1;
      requirements.push({
        id: `REQ-${String(n).padStart(3, '0')}`,
        text,
        type: typeOf(line),
        priority: priorityOf(line),
        source: { doc: doc.path, page: null, line: li + 1, anchor: `RAW_TEXT.md#doc-${di + 1}` },
        tags: [],
        risk: scanSafety(text).map((f) => f.domain),
        sensitivity: [...new Set(scanSensitivity(text).hits.map((h) => h.kind))],
        status: doc.status === 'needs_review' ? 'needs_review' : 'extracted',
      });
    }
  });
  return { version: REQ_VERSION, generatedAt: nowIso, documents: docs.map((d) => d.path), requirements };
}
