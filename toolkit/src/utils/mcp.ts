// MCP source-of-truth grounding directive. Injected into NEXT_PROMPT/TASK_BRIEF as GUIDANCE only — the
// toolkit cannot force tool use, so this is "inject + report", never "enforce". Approved MCPs and
// security defaults are read from presets/mcp-policy.json with an embedded fallback.

import { join } from 'node:path';
import { readJson } from './io.js';
import { presetsDir } from './paths.js';

interface McpPolicy {
  approved?: Array<{ name: string; use: string }>;
  securityDefaults?: string[];
}

const FALLBACK: Required<McpPolicy> = {
  approved: [
    { name: 'Context7', use: 'package/library/API/framework docs (never memory)' },
    { name: 'GitHub', use: 'repo, PRs, issues, commits, CI context' },
    { name: 'Playwright', use: 'browser/UI verification' },
    { name: 'Filesystem', use: 'scoped project files only' },
    { name: 'DB (read-only)', use: 'schema/table/column truth' },
  ],
  securityDefaults: [
    'filesystem scoped to the current project',
    'database read-only; production DB disabled',
    'no cloud write access',
    'no destructive commands without explicit approval',
    'never install untrusted MCP servers globally',
  ],
};

export function loadMcpPolicy(): Required<McpPolicy> {
  const p = readJson<McpPolicy>(join(presetsDir(), 'mcp-policy.json'));
  return {
    approved: p?.approved && p.approved.length > 0 ? p.approved : FALLBACK.approved,
    securityDefaults: p?.securityDefaults && p.securityDefaults.length > 0 ? p.securityDefaults : FALLBACK.securityDefaults,
  };
}

export function mcpDirective(): string {
  const pol = loadMcpPolicy();
  const lines: string[] = [];
  lines.push('Use approved free/OSS MCPs as ground truth — never guess when an MCP can supply the real source.');
  lines.push('If an MCP is unavailable, say so and proceed with safe assumptions (do not fabricate).');
  for (const m of pol.approved) lines.push(`- ${m.name}: ${m.use}`);
  lines.push('Security defaults: ' + pol.securityDefaults.join('; ') + '.');
  return lines.join('\n');
}
