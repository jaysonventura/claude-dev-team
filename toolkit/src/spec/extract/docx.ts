// .docx text extraction via mammoth (lazy, non-literal specifier to avoid a hard type dependency).

import { readFileSync } from 'node:fs';

export async function extractDocx(path: string): Promise<{ text: string; pages: number | null }> {
  const specifier = 'mammoth';
  const mod: unknown = await import(specifier);
  const m = mod as { extractRawText?: (o: unknown) => Promise<{ value?: string }>; default?: { extractRawText?: (o: unknown) => Promise<{ value?: string }> } };
  const fn = m.extractRawText ?? m.default?.extractRawText;
  if (!fn) throw new Error('mammoth.extractRawText unavailable');
  const res = await fn({ buffer: readFileSync(path) });
  return { text: res.value ?? '', pages: null };
}
