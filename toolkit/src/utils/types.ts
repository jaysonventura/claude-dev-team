// Shared types for the toolkit. Pure type declarations — no runtime code.

export type Tier = 'T0' | 'T1' | 'T2' | 'T3';
export type ModelTier = 'haiku' | 'sonnet' | 'opus';
export type EnhanceMode = 'auto' | 'always' | 'off';
export type Backend = 'haiku' | 'ollama' | 'deterministic';

export interface PromptConfig {
  enhance: boolean;
  mode: EnhanceMode;
  confidenceThreshold: number;
  timeoutMs: number;
  model: string;
  minChars: number;
  maxPerSession: number;
  maxUsd: number;
  maxContextChars: number;
  backend: Backend;
  localModel: string;
}

export interface SpecConfig {
  auto: boolean;
  externalAiAllowed: boolean;
  ocrEnabled: boolean;
}

export interface VerifyConfig {
  docsExempt: boolean;
}

export interface CdtConfig {
  enabled: boolean;
  redact: boolean;
  prompt: PromptConfig;
  spec: SpecConfig;
  verify: VerifyConfig;
}

export type Severity = 'low' | 'medium' | 'high';

export interface SafetyFinding {
  domain: string;
  severity: Severity;
  match: string;
  evidenceRedacted: string;
}

export interface RoutingAgent {
  name: string;
  owns: string[];
  reason: string;
}

export interface RoutingResult {
  version: string;
  generatedAt: string;
  promptRedacted: string;
  promptHash: string;
  tier: Tier;
  model: ModelTier;
  confidence: number;
  advisory: true;
  enhanced: boolean;
  degraded: boolean;
  risk: { flagged: boolean; domains: string[]; floor: Tier | 'none' };
  securityReview: boolean;
  agents: RoutingAgent[];
  gates: string[];
  safety: { findings: SafetyFinding[] };
  notes: string;
}

export type VerifyType = 'test' | 'build' | 'lint' | 'typecheck' | 'other';

export interface VerifyEvent {
  ts: string;
  command: string;
  type: VerifyType;
  exitCode: number | null;
  cwd: string;
  source: 'cdt-verify' | 'hook';
}

export type TaskStatus = 'done' | 'partial' | 'blocked' | 'failed' | 'needs_review';
export type VerificationState = 'passed' | 'failed' | 'not_run';

export interface TaskResult {
  status: TaskStatus;
  task: string;
  result: string;
  verification: VerificationState;
  artifact: string | null;
  nextStep: string;
}

export interface SensitivityHit {
  kind: string;
  match: string;
}

export interface SensitivityResult {
  sensitive: boolean;
  // failClosed=true means we treated an ambiguous/erroring scan as sensitive.
  failClosed: boolean;
  hits: SensitivityHit[];
}
