// PDF text extraction via pdf-parse. Imported through its internal lib path (and via a non-literal
// specifier) to bypass pdf-parse's debug-mode shim and avoid a hard type dependency.

import { readFileSync } from 'node:fs';

export async function extractPdf(path: string): Promise<{ text: string; pages: number | null }> {
  const specifier = 'pdf-parse/lib/pdf-parse.js';
  const mod: unknown = await import(specifier);
  const pdfParse = ((mod as { default?: unknown }).default ?? mod) as (b: Buffer) => Promise<{ text?: string; numpages?: number }>;
  const data = await pdfParse(readFileSync(path));
  return { text: data.text ?? '', pages: typeof data.numpages === 'number' ? data.numpages : null };
}
