// Detect spec/requirement DOCUMENTS referenced in a prompt — and ONLY those. Source code, project
// folders, non-existent paths, URLs, and globs are excluded, so auto-`cdt-spec` never misfires.
//
// Rules:
//   1. The token must resolve to an existing regular FILE (directories fail `isFile()`).
//   2. .pdf / .docx / .doc           → always a spec document.
//   3. .md / .markdown / .txt / .rtf → spec ONLY if the basename signals requirements
//      (requirements / spec / srs / prd / brief / scope / user story / acceptance criteria).
//   4. Source-code extensions are hard-excluded (never a spec).

import { statSync } from 'node:fs';
import { basename, extname, isAbsolute, resolve } from 'node:path';

const SPEC_EXTS = new Set(['.pdf', '.docx', '.doc']);
const DOC_TEXT_EXTS = new Set(['.md', '.markdown', '.txt', '.rtf']);

// Hard-excluded — if a path has one of these, it's code/config, never a spec document.
const SOURCE_EXTS = new Set([
  '.ts', '.tsx', '.js', '.jsx', '.mjs', '.cjs', '.py', '.go', '.java', '.rb', '.rs', '.c', '.h',
  '.cc', '.cpp', '.hpp', '.cs', '.php', '.swift', '.kt', '.kts', '.scala', '.m', '.mm', '.sql',
  '.json', '.jsonc', '.yaml', '.yml', '.toml', '.ini', '.xml', '.html', '.htm', '.css', '.scss',
  '.less', '.sh', '.bash', '.zsh', '.ps1', '.lock', '.env', '.gradle', '.dockerfile', '.makefile',
]);

const REQUIREMENT_NAME = /(require|spec\b|specification|srs|prd|brief|scope|user.?stor|acceptance|criteria)/i;

// Path-like tokens: a run of path chars containing a dotted extension (1–8 chars). Strips surrounding
// quotes/backticks/parens/commas via the character class.
const PATH_TOKEN = /[A-Za-z0-9_@./~+-]+\.[A-Za-z0-9]{1,8}/g;

/** Return absolute paths of spec documents referenced in the prompt (excludes source & folders). */
export function detectSpecFiles(prompt: string, root: string): string[] {
  const out = new Set<string>();
  const tokens = prompt.match(PATH_TOKEN) ?? [];
  for (const raw of tokens) {
    const tok = raw.replace(/[).,;:]+$/, ''); // trailing punctuation
    if (/^[a-z][a-z0-9+.-]*:\/\//i.test(tok)) continue; // URL
    const ext = extname(tok).toLowerCase();
    if (!ext || SOURCE_EXTS.has(ext)) continue;
    const isSpec = SPEC_EXTS.has(ext);
    const isDocText = DOC_TEXT_EXTS.has(ext) && REQUIREMENT_NAME.test(basename(tok));
    if (!isSpec && !isDocText) continue;
    const abs = isAbsolute(tok) ? tok : resolve(root, tok);
    try {
      if (statSync(abs).isFile()) out.add(abs); // a directory/folder fails isFile()
    } catch {
      // not a real file — skip
    }
  }
  return [...out];
}
