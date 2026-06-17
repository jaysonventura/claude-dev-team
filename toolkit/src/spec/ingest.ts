// Ingest source documents into a normalized form. Deterministic; OCR is local-only and gated.

import { existsSync } from 'node:fs';
import { extname } from 'node:path';
import { scanSensitivity } from '../validators/sensitivity.js';
import { extractDocx } from './extract/docx.js';
import { extractImage } from './extract/image.js';
import { extractPdf } from './extract/pdf.js';
import { extractText } from './extract/text.js';
import type { IngestedDoc, Section } from './types.js';

const IMAGE_EXTS = new Set(['.png', '.jpg', '.jpeg', '.gif', '.bmp', '.tiff', '.webp']);

function sectionsOf(text: string): Section[] {
  const lines = text.split('\n');
  const secs: Section[] = [];
  let cur: Section | undefined;
  for (let i = 0; i < lines.length; i += 1) {
    const m = /^(#{1,6})\s+(.*)$/.exec((lines[i] ?? '').trim());
    if (m) {
      if (cur) {
        cur.endLine = i;
        secs.push(cur);
      }
      cur = { heading: (m[2] ?? '').trim(), startLine: i + 1, endLine: i + 1 };
    }
  }
  if (cur) {
    cur.endLine = lines.length;
    secs.push(cur);
  }
  if (secs.length === 0 && lines.length > 0) secs.push({ heading: 'document', startLine: 1, endLine: lines.length });
  return secs;
}

function finalize(path: string, type: string, text: string, pages: number | null, status: IngestedDoc['status'], extra: Partial<IngestedDoc> = {}): IngestedDoc {
  const sens = scanSensitivity(text);
  return {
    path,
    type,
    text,
    pages,
    sections: sectionsOf(text),
    ocrConfidence: extra.ocrConfidence ?? null,
    status,
    sensitivity: [...new Set(sens.hits.map((h) => h.kind))],
    note: extra.note,
  };
}

export async function ingest(paths: string[], ocrEnabled: boolean): Promise<IngestedDoc[]> {
  const docs: IngestedDoc[] = [];
  for (const p of paths) {
    if (!existsSync(p)) {
      docs.push(finalize(p, 'missing', '', null, 'needs_review', { note: 'file not found' }));
      continue;
    }
    const ext = extname(p).toLowerCase();
    try {
      if (ext === '.md' || ext === '.markdown' || ext === '.txt') {
        const { text, pages } = extractText(p);
        docs.push(finalize(p, ext === '.txt' ? 'txt' : 'md', text, pages, 'extracted'));
      } else if (ext === '.pdf') {
        const { text, pages } = await extractPdf(p);
        docs.push(finalize(p, 'pdf', text, pages, text.trim() ? 'extracted' : 'needs_review', text.trim() ? {} : { note: 'no extractable text (scanned PDF?)' }));
      } else if (ext === '.docx') {
        const { text, pages } = await extractDocx(p);
        docs.push(finalize(p, 'docx', text, pages, text.trim() ? 'extracted' : 'needs_review'));
      } else if (IMAGE_EXTS.has(ext)) {
        const r = await extractImage(p, ocrEnabled);
        docs.push(finalize(p, 'image', r.text, null, r.status, { ocrConfidence: r.ocrConfidence, note: r.status === 'needs_review' ? 'image/diagram — low/disabled OCR → NEEDS_REVIEW' : undefined }));
      } else {
        docs.push(finalize(p, 'unknown', '', null, 'needs_review', { note: 'unsupported file type' }));
      }
    } catch (e) {
      docs.push(finalize(p, ext.replace('.', '') || 'unknown', '', null, 'needs_review', { note: `extract failed: ${String(e)}` }));
    }
  }
  return docs;
}
