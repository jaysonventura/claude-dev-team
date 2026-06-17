// Thin wrappers over node:util parseArgs for the small CLI surface. Zero external deps.

import { parseArgs, type ParseArgsConfig } from 'node:util';

export interface Parsed {
  values: Record<string, string | boolean | undefined>;
  positionals: string[];
}

export function parse(
  argv: string[],
  options: NonNullable<ParseArgsConfig['options']> = {},
): Parsed {
  const { values, positionals } = parseArgs({
    args: argv,
    options,
    allowPositionals: true,
    strict: false,
  });
  return { values: values as Parsed['values'], positionals };
}

/**
 * Split a `cdt-verify -- <command...>` invocation into its trailing command. Everything after the first
 * standalone `--` is the verbatim command to run.
 */
export function commandAfterDoubleDash(argv: string[]): string[] {
  const idx = argv.indexOf('--');
  if (idx === -1) return [];
  return argv.slice(idx + 1);
}
