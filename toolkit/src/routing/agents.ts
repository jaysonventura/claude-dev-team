// Keyword/domain → agent recommendation. Embedded defaults (deterministic + testable); a project may
// override via presets/routing-rules.json shipped with the package and copied by `cdt init`.

import { join } from 'node:path';
import { readJson } from '../utils/io.js';
import { presetsDir } from '../utils/paths.js';
import type { RoutingAgent } from '../utils/types.js';
import type { Classification } from './classify.js';

interface RosterEntry {
  name: string;
  owns: string[];
  match: string[];
  wave?: number;
}

const DEFAULT_ROSTER: RosterEntry[] = [
  { name: 'backend-engineer', owns: ['api/**', 'server/**'], match: ['api', 'server', 'endpoint', 'backend', 'service', 'auth', 'payment', 'route'] },
  { name: 'frontend-engineer', owns: ['ui/**', 'client/**'], match: ['ui', 'component', 'page', 'css', 'frontend', 'react', 'vue', 'svelte', 'button', 'form', 'navbar'] },
  { name: 'mobile-engineer', owns: ['mobile/**', 'app/**'], match: ['mobile', 'ios', 'android', 'swift', 'kotlin', 'react native', 'expo', 'flutter'] },
  { name: 'data-engineer', owns: ['db/**', 'migrations/**'], match: ['database', 'db ', 'schema', 'migration', 'query', 'sql', 'index', 'etl'] },
  { name: 'devops-engineer', owns: ['infra/**', 'ci/**'], match: ['infra', 'ci', 'cd', 'docker', 'kubernetes', 'terraform', 'deploy', 'pipeline'] },
  { name: 'qa-engineer', owns: ['test/**', 'tests/**'], match: ['test', 'spec', 'e2e', 'coverage', 'qa'] },
  { name: 'technical-writer', owns: ['docs/**'], match: ['docs', 'documentation', 'readme', 'changelog', 'guide'] },
];

function loadRoster(): RosterEntry[] {
  const fromPreset = readJson<{ roster?: RosterEntry[] }>(join(presetsDir(), 'routing-rules.json'));
  if (fromPreset && Array.isArray(fromPreset.roster) && fromPreset.roster.length > 0) {
    return fromPreset.roster;
  }
  return DEFAULT_ROSTER;
}

/** Recommend an advisory agent dispatch. Never auto-escalates; the orchestrator decides. */
export function recommendAgents(prompt: string, c: Classification): RoutingAgent[] {
  const hay = ' ' + prompt.toLowerCase() + ' ';
  const roster = loadRoster();
  const out: RoutingAgent[] = [];

  for (const r of roster) {
    if (r.match.some((m) => hay.includes(m))) {
      out.push({ name: r.name, owns: r.owns, reason: `matched ${r.match.filter((m) => hay.includes(m)).join(', ')}` });
    }
  }

  // Wave 0 architect for opus/T3 work.
  if (c.model === 'opus' || c.tier === 'T3') {
    out.unshift({ name: 'architect', owns: [], reason: 'design/architecture or cross-cutting work' });
  }
  // Wave 2 reviewers.
  if (c.tier === 'T2' || c.tier === 'T3') {
    out.push({ name: 'code-reviewer', owns: [], reason: 'independent review at T2+' });
  }
  if (c.securityReview) {
    out.push({ name: 'security-reviewer', owns: [], reason: 'risk-flagged — mandatory security review (veto on risk≥medium)' });
  }
  // Trivial fallback.
  if (out.length === 0 && c.tier === 'T0') {
    out.push({ name: 'fast-ops', owns: [], reason: 'trivial mechanical op' });
  }

  // De-dupe by name (keep first reason).
  const seen = new Set<string>();
  return out.filter((a) => (seen.has(a.name) ? false : (seen.add(a.name), true)));
}

const DEFAULT_GATES = ['fmt', 'lint', 'typecheck', 'unit', 'build', 'review'];

export function recommendGates(c: Classification): string[] {
  const preset = readJson<{ gates?: string[] }>(join(presetsDir(), 'quality-gates.json'));
  const base = preset && Array.isArray(preset.gates) && preset.gates.length > 0 ? preset.gates.slice() : DEFAULT_GATES.slice();
  if (c.securityReview && !base.includes('security-review')) base.push('security-review');
  return base;
}
