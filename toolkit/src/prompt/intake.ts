// Normalize a raw user prompt and surface cheap structural facts the hook gate needs.

import { TRIVIAL, hasAny, lc } from '../routing/keywords.js';

export interface Intake {
  raw: string;
  normalized: string;
  isSlashCommand: boolean;
  isTrivial: boolean;
  length: number;
}

export function intake(raw: string): Intake {
  const normalized = raw.replace(/\s+/g, ' ').trim();
  return {
    raw,
    normalized,
    isSlashCommand: normalized.startsWith('/'),
    isTrivial: hasAny(lc(normalized), TRIVIAL),
    length: normalized.length,
  };
}
