import { readFileSync } from 'node:fs';

export function extractText(path: string): { text: string; pages: number | null } {
  return { text: readFileSync(path, 'utf8'), pages: null };
}
