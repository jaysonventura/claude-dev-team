// Configuration resolution with explicit precedence:
//   packaged defaults  <  project .claude/cdt.config.json  <  environment variables.

import { mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { homedir } from 'node:os';
import { dirname, join } from 'node:path';
import { claudeDir, projectRoot } from './paths.js';
import type { Backend, CdtConfig, EnhanceMode } from './types.js';

export const DEFAULT_CONFIG: CdtConfig = {
  enabled: true,
  toolkitEnabled: true,
  redact: true,
  prompt: {
    enhance: true,
    mode: 'auto',
    confidenceThreshold: 0.75,
    timeoutMs: 12000,
    model: 'claude-haiku-4-5',
    minChars: 40,
    maxPerSession: 25,
    maxUsd: 0.1,
    maxContextChars: 4000,
    backend: 'haiku',
    localModel: 'qwen3:8b',
  },
  spec: {
    auto: false,
    externalAiAllowed: false,
    ocrEnabled: false,
  },
  verify: {
    docsExempt: true,
  },
};

type Env = Record<string, string | undefined>;

function bool(v: string | undefined, fallback: boolean): boolean {
  if (v === undefined) return fallback;
  return /^(1|true|yes|on)$/i.test(v.trim());
}

function num(v: string | undefined, fallback: number): number {
  if (v === undefined) return fallback;
  const n = Number(v);
  return Number.isFinite(n) ? n : fallback;
}

function oneOf<T extends string>(v: string | undefined, allowed: readonly T[], fallback: T): T {
  if (v !== undefined && (allowed as readonly string[]).includes(v)) return v as T;
  return fallback;
}

/** Shallow-typed deep merge of a partial project config onto a base config. */
function mergeProject(base: CdtConfig, project: unknown): CdtConfig {
  if (!project || typeof project !== 'object') return base;
  const p = project as Record<string, unknown>;
  const out: CdtConfig = {
    ...base,
    prompt: { ...base.prompt },
    spec: { ...base.spec },
    verify: { ...base.verify },
  };
  if (typeof p.enabled === 'boolean') out.enabled = p.enabled;
  if (typeof p.toolkitEnabled === 'boolean') out.toolkitEnabled = p.toolkitEnabled;
  if (typeof p.redact === 'boolean') out.redact = p.redact;
  if (p.prompt && typeof p.prompt === 'object') Object.assign(out.prompt, p.prompt);
  if (p.spec && typeof p.spec === 'object') Object.assign(out.spec, p.spec);
  if (p.verify && typeof p.verify === 'object') Object.assign(out.verify, p.verify);
  return out;
}

function applyEnv(cfg: CdtConfig, env: Env): CdtConfig {
  const out: CdtConfig = {
    ...cfg,
    prompt: { ...cfg.prompt },
    spec: { ...cfg.spec },
    verify: { ...cfg.verify },
  };
  out.enabled = bool(env.CDT_ENABLED, out.enabled);
  out.toolkitEnabled = bool(env.CDT_TOOLKIT_ENABLED, out.toolkitEnabled);
  out.redact = bool(env.CDT_REDACT, out.redact);

  out.prompt.enhance = bool(env.CDT_PROMPT_ENHANCE, out.prompt.enhance);
  out.prompt.mode = oneOf<EnhanceMode>(env.CDT_PROMPT_ENHANCE_MODE, ['auto', 'always', 'off'], out.prompt.mode);
  out.prompt.confidenceThreshold = num(env.CDT_PROMPT_CONFIDENCE_THRESHOLD, out.prompt.confidenceThreshold);
  out.prompt.timeoutMs = num(env.CDT_PROMPT_TIMEOUT_MS, out.prompt.timeoutMs);
  out.prompt.model = env.CDT_PROMPT_MODEL ?? out.prompt.model;
  out.prompt.minChars = num(env.CDT_PROMPT_MIN_CHARS, out.prompt.minChars);
  out.prompt.maxPerSession = num(env.CDT_PROMPT_MAX_PER_SESSION, out.prompt.maxPerSession);
  out.prompt.maxUsd = num(env.CDT_PROMPT_MAX_USD, out.prompt.maxUsd);
  out.prompt.maxContextChars = num(env.CDT_MAX_CONTEXT_CHARS, out.prompt.maxContextChars);
  out.prompt.localModel = env.LOCAL_PROMPT_MODEL ?? out.prompt.localModel;
  if (env.CDT_PROMPT_BACKEND) {
    out.prompt.backend = oneOf<Backend>(env.CDT_PROMPT_BACKEND, ['haiku', 'ollama', 'deterministic'], out.prompt.backend);
  }

  out.spec.auto = bool(env.CDT_SPEC_AUTO, out.spec.auto);
  out.spec.externalAiAllowed = bool(env.CDT_EXTERNAL_AI_ALLOWED, out.spec.externalAiAllowed);
  out.spec.ocrEnabled = bool(env.CDT_OCR_ENABLED, out.spec.ocrEnabled);

  out.verify.docsExempt = bool(env.CDT_VERIFY_DOCS_EXEMPT, out.verify.docsExempt);
  return out;
}

/** Path of the global env file (~/.claude/claude-dev-team.env), overridable via CDT_ENV_FILE. */
function globalEnvPath(env: Env): string {
  return env.CDT_ENV_FILE ?? join(homedir(), '.claude', 'claude-dev-team.env');
}

/** Read the global env file into a KEY=VALUE map (the surface cdt-config / the menu bar write to). */
export function readGlobalEnvFile(env: Env = process.env): Env {
  const out: Env = {};
  try {
    const raw = readFileSync(globalEnvPath(env), 'utf8');
    for (const line of raw.split('\n')) {
      const m = /^([A-Za-z][A-Za-z0-9_]*)=(.*)$/.exec(line.trim());
      if (m && m[1] !== undefined) out[m[1]] = m[2] ?? '';
    }
  } catch {
    // no global env file — fine.
  }
  return out;
}

/** Upsert KEY=VALUE in the global env file (0600). Used by `cdt enable|disable`. Returns the path. */
export function setGlobalEnv(key: string, value: string, env: Env = process.env): string {
  const path = globalEnvPath(env);
  let lines: string[] = [];
  try {
    lines = readFileSync(path, 'utf8')
      .split('\n')
      .filter((l) => l.trim() !== '' && !l.trim().startsWith(`${key}=`));
  } catch {
    // new file
  }
  lines.push(`${key}=${value}`);
  try {
    mkdirSync(dirname(path), { recursive: true });
  } catch {
    /* best effort */
  }
  writeFileSync(path, lines.join('\n') + '\n', { mode: 0o600 });
  return path;
}

/**
 * Load the effective config for a project root. Precedence (low → high):
 *   packaged defaults  <  global ~/.claude/claude-dev-team.env  <  project .claude/cdt.config.json  <  process env.
 */
export function loadConfig(root: string = projectRoot(), env: Env = process.env): CdtConfig {
  let cfg = DEFAULT_CONFIG;
  cfg = applyEnv(cfg, readGlobalEnvFile(env)); // global toggles (cdt-config / menu bar)
  try {
    cfg = mergeProject(cfg, JSON.parse(readFileSync(join(claudeDir(root), 'cdt.config.json'), 'utf8')));
  } catch {
    // No project config (or unreadable) — safe-degrade.
  }
  return applyEnv(cfg, env); // explicit process env wins
}
