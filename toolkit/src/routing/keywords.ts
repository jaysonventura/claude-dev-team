// Keyword sets that drive deterministic routing. RISK / HARD / TRIVIAL mirror the existing Bash
// `cdt-route`; OPUS_ESCALATION encodes the (narrow) cases where Opus is warranted per the plan
// (architecture, severe security, production-release review, major refactor, complex root-cause,
// security-architecture redesign). RISK alone routes Sonnet + security-reviewer, NOT Opus.

export const RISK: string[] = [
  'auth', 'login', 'password', 'oauth', 'token', 'payment', 'billing', 'stripe', 'secret',
  'credential', 'crypto', 'encrypt', 'infra', 'terraform', 'kubernetes', 'migration', 'rbac',
  'permission', 'security', 'vulnerab', 'injection', 'xss', 'csrf',
];

export const HARD: string[] = [
  'architect', 'design', 'redesign', 'refactor', 'ambiguous', 'tricky', 'complex', 'concurrency',
  'race condition', 'deadlock', 'distributed', 'algorithm', 'optimi', 'performance', 'root cause',
  'debug', 'review', 'audit', 'tradeoff', 'decide', 'strategy', 'api design', 'data model',
];

export const TRIVIAL: string[] = [
  'rename', 'typo', 'whitespace', 'reformat', 'prettier', 'lint fix', 'sort import',
  'add a comment', 'bump version', 'reword', 'move file', 'find and replace',
  'find/replace', 'rename variable', 'fix indentation', 'spelling',
];

// Narrow set that justifies Opus.
export const OPUS_ESCALATION: string[] = [
  'architecture', 're-architect', 'rearchitect', 'major refactor', 'large refactor', 'rewrite',
  'production release', 'release review', 'prod release', 'root cause', 'security architecture',
  'threat model', 'exploit', 'breach', 'severe', 'critical vulnerability', 'security redesign',
];

// Vague verbs/markers that lower routing confidence when not accompanied by specifics.
export const VAGUE_MARKERS: string[] = [
  'fix something', 'make it better', 'improve', 'clean up', 'handle', 'somehow', 'etc', 'and so on',
  'do the needful', 'sort it out', 'figure out', 'whatever', 'stuff', 'things',
];

// Signals the prompt references files/specs (a reason to enhance + write a brief).
export const FILE_SPEC_MARKERS: string[] = [
  '.md', '.pdf', '.docx', '.ts', '.tsx', '.js', '.py', '.json', '@', 'spec', 'requirements',
  'attached', 'document', 'see file',
];

export function lc(s: string): string {
  return ' ' + s.toLowerCase() + ' ';
}

export function hasAny(haystackLower: string, words: string[]): boolean {
  return words.some((w) => haystackLower.includes(w));
}

export function matchedAny(haystackLower: string, words: string[]): string[] {
  return words.filter((w) => haystackLower.includes(w));
}
