#!/usr/bin/env node
// cdt-verify -- <command>
// Runs <command>, captures its real exit code, and records the ONLY trusted verification evidence.
// Exits with the command's own exit code so it is a transparent wrapper.

import { commandAfterDoubleDash } from '../utils/args.js';
import { error, info } from '../utils/log.js';
import { projectRoot } from '../utils/paths.js';
import { runVerify } from '../verify/events.js';

const cmd = commandAfterDoubleDash(process.argv.slice(2));
if (cmd.length === 0) {
  error('usage: cdt-verify -- <command>');
  process.exit(2);
}

const root = projectRoot();
const { exitCode, type } = runVerify(cmd, root);
info(`recorded trusted verify event (type=${type}, exitCode=${exitCode})`);
process.exit(exitCode);
