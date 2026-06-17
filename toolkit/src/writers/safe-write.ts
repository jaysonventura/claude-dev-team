// Every artifact passes through redaction before it is persisted. Markdown artifacts are redacted as a
// whole; JSON artifacts are constructed with redacted fields and serialized by the caller.

import { writeArtifact, type WriteResult } from '../utils/io.js';
import { projectRoot } from '../utils/paths.js';
import type { CdtConfig } from '../utils/types.js';
import { redact } from '../validators/redact.js';

export function writeRedacted(path: string, content: string, cfg: CdtConfig, root: string = projectRoot()): WriteResult {
  const finalContent = cfg.redact ? redact(content) : content;
  return writeArtifact(path, finalContent, root);
}
