// Images/diagrams: NEEDS_REVIEW by default. Only when LOCAL OCR is enabled (CDT_OCR_ENABLED) AND the OCR
// is clearly confident do we treat the extracted text as usable. OCR runs on-device (tesseract.js).

export async function extractImage(
  path: string,
  ocrEnabled: boolean,
): Promise<{ text: string; ocrConfidence: number | null; status: 'extracted' | 'needs_review' }> {
  if (!ocrEnabled) return { text: '', ocrConfidence: null, status: 'needs_review' };
  try {
    const specifier = 'tesseract.js';
    const mod: unknown = await import(specifier);
    const tess = mod as { recognize: (img: string, lang: string) => Promise<{ data?: { text?: string; confidence?: number } }> };
    const res = await tess.recognize(path, 'eng');
    const conf = res.data?.confidence ?? 0;
    const text = res.data?.text ?? '';
    if (conf < 60 || text.trim().length < 10) return { text, ocrConfidence: conf, status: 'needs_review' };
    return { text, ocrConfidence: conf, status: 'extracted' };
  } catch {
    return { text: '', ocrConfidence: null, status: 'needs_review' };
  }
}
