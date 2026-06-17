#!/usr/bin/env node
// `cdt` umbrella CLI: init | status | version.

import { join } from 'node:path';
import { loadConfig, setGlobalEnv } from '../utils/config.js';
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
  case 'enable': {
    const p = setGlobalEnv('CDT_TOOLKIT_ENABLED', '1');
    process.stdout.write(`claude-dev-team toolkit: ENABLED (${p})\n`);
    break;
  }
  case 'disable': {
    const p = setGlobalEnv('CDT_TOOLKIT_ENABLED', '0');
    process.stdout.write(`claude-dev-team toolkit: DISABLED — core CDT is unaffected (${p})\n`);
    break;
  }
  case 'config':
    process.stdout.write(JSON.stringify(loadConfig(), null, 2) + '\n');
    break;
  case 'version':
  case '--version':
  case '-v':
    process.stdout.write(`claude-dev-team-toolkit ${version()}\n`);
    break;
  default:
    process.stderr.write('usage: cdt <init|status|enable|disable|config|version>\n');
    process.exit(sub ? 2 : 0);
}
