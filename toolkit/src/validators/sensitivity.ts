// Sensitivity scanner for prompts and documents. FAILS CLOSED: any error/uncertainty => sensitive.
// Used by the prompt pre-gate (never send sensitive prompts to an external model) and the spec
// external-AI gate.

import type { SensitivityResult } from '../utils/types.js';
import { findSecrets } from './redact.js';

interface Category {
  kind: string;
  words: string[];
}

const SENSITIVE_CATEGORIES: Category[] = [
  { kind: 'payroll', words: ['payroll', 'salary', 'wage', 'compensation', 'paystub', 'w-2', 'w2 form'] },
  {
    kind: 'user-data-pii',
    words: ['ssn', 'social security', 'date of birth', 'passport number', 'national id', 'home address'],
  },
  {
    kind: 'legal-contract',
    words: ['non-disclosure', 'nda', 'contract clause', 'legal agreement', 'attorney', 'litigation'],
  },
  {
    kind: 'credentials',
    words: ['password', 'passwd', 'credential', 'api key', 'apikey', 'access token', 'private key', 'client secret'],
  },
  {
    kind: 'production',
    words: ['production database', 'prod db', 'prod database', '.env.production', 'production credentials', 'production secret'],
  },
  {
    kind: 'payment-auth-logic',
    words: ['credit card', 'card number', 'cvv', 'iban', 'bank account', 'routing number', 'stripe secret'],
  },
  {
    kind: 'business-confidential',
    words: ['trade secret', 'proprietary', 'internal only', 'do not distribute', 'confidential'],
  },
];

/** Shannon entropy (bits/char) of a string. */
function entropy(s: string): number {
  const freq = new Map<string, number>();
  for (const ch of s) freq.set(ch, (freq.get(ch) ?? 0) + 1);
  let h = 0;
  for (const c of freq.values()) {
    const p = c / s.length;
    h -= p * Math.log2(p);
  }
  return h;
}

/** Long, mixed-charset, high-entropy tokens that look like secrets the regexes didn't catch. */
function highEntropyTokens(text: string): string[] {
  const out: string[] = [];
  for (const tok of text.split(/\s+/)) {
    if (tok.length >= 24 && /[A-Za-z]/.test(tok) && /[0-9]/.test(tok) && entropy(tok) >= 3.5) {
      out.push(tok);
    }
  }
  return out;
}

export function scanSensitivity(input: string): SensitivityResult {
  try {
    const lower = input.toLowerCase();
    const hits: SensitivityResult['hits'] = [];
    for (const cat of SENSITIVE_CATEGORIES) {
      for (const w of cat.words) {
        if (lower.includes(w)) hits.push({ kind: cat.kind, match: w });
      }
    }
    for (const s of findSecrets(input)) hits.push({ kind: `secret:${s.kind}`, match: s.match });
    for (const t of highEntropyTokens(input)) hits.push({ kind: 'high-entropy', match: t.slice(0, 12) + '…' });
    return { sensitive: hits.length > 0, failClosed: false, hits };
  } catch {
    // Uncertainty => treat as sensitive.
    return { sensitive: true, failClosed: true, hits: [] };
  }
}
