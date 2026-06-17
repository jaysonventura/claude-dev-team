#!/usr/bin/env node
// `cdt` umbrella CLI: init | status | version.

import { join } from 'node:path';
import { readJson } from '../utils/io.js';
import { packageRoot } from '../utils/paths.js';
import { runInit } from './init.js';
import { runStatus } from './status.js';

function version(): string {
  const pkg = readJson<{ version?: string }>(join(packageRoot(), 'package.json'));
  return pkg?.version ?? '0.0.0';
}

const sub = process.argv[2];
switch (sub) {
  case 'init':
    runInit();
    break;
  case 'status':
    runStatus();
    break;
  case 'version':
  case '--version':
  case '-v':
    process.stdout.write(`claude-dev-team-toolkit ${version()}\n`);
    break;
  default:
    process.stderr.write('usage: cdt <init|status|version>\n');
    process.exit(sub ? 2 : 0);
}
