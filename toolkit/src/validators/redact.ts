// Redaction: mask secrets/credentials/PII to ‹redacted:kind› before any artifact is written or any
// context is emitted. Conservative patterns only (avoid mangling ordinary prose).

export interface RedactPattern {
  kind: string;
  re: RegExp;
  /** Optional custom replacer; receives (match, group1, group2). Return null to leave the text unchanged. */
  replace?: (match: string, g1: string, g2: string) => string | null;
}

// NOTE: order matters — multi-line / structured secrets first.
export const SECRET_PATTERNS: RedactPattern[] = [
  {
    kind: 'private-key',
    re: /-----BEGIN (?:RSA |EC |OPENSSH |DSA |PGP )?PRIVATE KEY-----[\s\S]*?-----END (?:RSA |EC |OPENSSH |DSA |PGP )?PRIVATE KEY-----/g,
  },
  { kind: 'anthropic-key', re: /\bsk-ant-[A-Za-z0-9_-]{20,}\b/g },
  { kind: 'openai-key', re: /\bsk-[A-Za-z0-9]{20,}\b/g },
  { kind: 'github-token', re: /\bgh[pousr]_[A-Za-z0-9]{20,}\b/g },
  { kind: 'slack-token', re: /\bxox[baprs]-[A-Za-z0-9-]{10,}\b/g },
  { kind: 'aws-access-key', re: /\bAKIA[0-9A-Z]{16}\b/g },
  { kind: 'jwt', re: /\beyJ[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}\b/g },
  { kind: 'bearer', re: /\bBearer\s+[A-Za-z0-9._-]{12,}/gi },
  { kind: 'connection-string', re: /\b[a-z][a-z0-9+.-]*:\/\/[^\s:@/]+:[^\s:@/]+@[^\s/]+/gi },
  {
    kind: 'secret-assignment',
    re: /\b(?:pass(?:word|wd)?|secret|token|api[_-]?key|client[_-]?secret)\b\s*[:=]\s*["']?[^\s"',;]{6,}/gi,
  },
  {
    // Natural-language secrets: "password is Hunter2zzzz", "passphrase was hunter2!", "the token of …".
    // Keeps the label, redacts only a secret-shaped value (has a digit/symbol or ≥10 chars) to avoid
    // mangling ordinary prose like "password is required".
    kind: 'secret-value',
    re: /\b(pass(?:word|wd|code)?|passphrase|secret|token|credential|passcode|pin)\b\s+(?:is|was|of)\s+["']?([A-Za-z0-9._+\-!@#$%^&*]{6,})/gi,
    replace: (_m: string, label: string, value: string): string | null =>
      /[0-9!@#$%^&*+]/.test(value) || value.length >= 10 ? `${label} ‹redacted:secret-value›` : null,
  },
  { kind: 'email', re: /\b[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}\b/g },
];

export interface RedactReport {
  text: string;
  hits: Array<{ kind: string; match: string }>;
}

/** Mask all known secret/PII patterns, returning the masked text and a list of hits. */
export function redactReport(input: string): RedactReport {
  const hits: Array<{ kind: string; match: string }> = [];
  let text = input;
  for (const p of SECRET_PATTERNS) {
    text = text.replace(p.re, (m: string, ...rest: unknown[]): string => {
      if (p.replace) {
        const g1 = typeof rest[0] === 'string' ? rest[0] : '';
        const g2 = typeof rest[1] === 'string' ? rest[1] : '';
        const out = p.replace(m, g1, g2);
        if (out === null) return m; // not secret-shaped — leave unchanged
        hits.push({ kind: p.kind, match: m });
        return out;
      }
      hits.push({ kind: p.kind, match: m });
      return `‹redacted:${p.kind}›`;
    });
  }
  return { text, hits };
}

/** Mask all known secret/PII patterns and return the masked text. */
export function redact(input: string): string {
  return redactReport(input).text;
}

/** Find secret hits without mutating the text (used by the sensitivity scanner). */
export function findSecrets(input: string): Array<{ kind: string; match: string }> {
  return redactReport(input).hits;
}
