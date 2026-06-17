// Safety-domain scanner for task routing. Flags the risk domains (production, delete, migration, auth,
// payment, secrets, permissions, file upload, public API, user data) with word-boundary matching and a
// small negative-context list to cut false positives ("design token" != auth token).

import type { SafetyFinding, Severity } from '../utils/types.js';
import { redact } from './redact.js';

interface Domain {
  domain: string;
  severity: Severity;
  words: string[];
}

const SAFETY_DOMAINS: Domain[] = [
  { domain: 'production', severity: 'high', words: ['production', 'prod deploy', 'prod release', 'go live', 'release to prod'] },
  { domain: 'delete', severity: 'high', words: ['delete', 'drop table', 'rm -rf', 'truncate', 'destroy', 'wipe data'] },
  { domain: 'migration', severity: 'high', words: ['migration', 'migrate', 'schema change', 'alter table', 'backfill'] },
  { domain: 'auth', severity: 'high', words: ['auth', 'login', 'logout', 'oauth', 'sso', 'session', 'jwt'] },
  { domain: 'payment', severity: 'high', words: ['payment', 'billing', 'stripe', 'invoice', 'checkout', 'refund'] },
  { domain: 'secrets', severity: 'high', words: ['secret', 'credential', 'api key', 'private key', 'token'] },
  { domain: 'permissions', severity: 'medium', words: ['permission', 'rbac', 'acl', 'authorization', 'privilege', 'grant access'] },
  { domain: 'file-upload', severity: 'medium', words: ['file upload', 'multipart', 'attachment upload'] },
  { domain: 'public-api', severity: 'medium', words: ['public api', 'public endpoint', 'external api', 'open endpoint'] },
  { domain: 'user-data', severity: 'medium', words: ['user data', 'pii', 'personal data', 'customer data', 'gdpr'] },
];

// Preceding qualifiers that neutralise an otherwise-risky word.
const NEGATIVE_CONTEXT: Record<string, string[]> = {
  token: ['design ', 'css ', 'sync ', 'reset ', 'pagination ', 'lexer ', 'word '],
  session: ['user session', 'study session', 'work session'],
};

function escapeRe(s: string): string {
  return s.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
}

function findWord(lower: string, word: string): number {
  const re = new RegExp(`(?:^|[^a-z0-9])${escapeRe(word)}(?:[^a-z0-9]|$)`, 'i');
  const m = re.exec(lower);
  if (!m) return -1;
  const negatives = NEGATIVE_CONTEXT[word];
  if (negatives) {
    const pre = lower.slice(Math.max(0, m.index - 18), m.index + word.length);
    if (negatives.some((n) => pre.includes(n))) return -1;
  }
  return m.index;
}

export function scanSafety(input: string): SafetyFinding[] {
  const lower = input.toLowerCase();
  const findings: SafetyFinding[] = [];
  const seen = new Set<string>();
  for (const d of SAFETY_DOMAINS) {
    for (const w of d.words) {
      const idx = findWord(lower, w);
      if (idx >= 0 && !seen.has(d.domain)) {
        seen.add(d.domain);
        const snippet = input.slice(Math.max(0, idx - 12), idx + w.length + 12);
        findings.push({ domain: d.domain, severity: d.severity, match: w, evidenceRedacted: redact(snippet).trim() });
        break;
      }
    }
  }
  return findings;
}
