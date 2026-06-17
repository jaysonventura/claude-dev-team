// Post-build: make the compiled CLI entrypoints executable (tsc does not set the +x bit).
// Fail-soft: a missing dist file is reported but never aborts the build on platforms
// where chmod is a no-op (e.g. Windows).
import { chmodSync, existsSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = dirname(dirname(fileURLToPath(import.meta.url)));
const bins = ['cdt.js', 'cdt-prompt.js', 'cdt-spec.js', 'cdt-verify.js'];

for (const b of bins) {
  const p = join(root, 'dist', 'cli', b);
  if (existsSync(p)) {
    try {
      chmodSync(p, 0o755);
    } catch {
      /* chmod unsupported (e.g. Windows) — npm bin shims still work */
    }
  } else {
    console.warn(`[postbuild] expected bin missing: ${p}`);
  }
}
