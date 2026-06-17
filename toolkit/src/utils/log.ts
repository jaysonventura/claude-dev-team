// Logging goes to STDERR so that CLI stdout stays clean (hook output / machine-readable results
// are written to stdout only).

const PREFIX = 'cdt';

export function info(msg: string): void {
  process.stderr.write(`${PREFIX}: ${msg}\n`);
}

export function warn(msg: string): void {
  process.stderr.write(`${PREFIX}: ⚠ ${msg}\n`);
}

export function error(msg: string): void {
  process.stderr.write(`${PREFIX}: ✖ ${msg}\n`);
}
