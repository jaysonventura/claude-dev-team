// Ajv validation with SAFE-DEGRADE semantics: a validator that throws never crashes the caller — it
// returns { valid:false, degraded:true } so the caller can fall back to conservative defaults.

import { Ajv, type ValidateFunction } from 'ajv';
import addFormatsModule from 'ajv-formats';
import {
  documentIndexSchema,
  requirementsSchema,
  routingSchema,
  taskResultSchema,
  verifyEventSchema,
} from './schemas.js';

export interface ValidationOutcome {
  valid: boolean;
  errors: string[];
  degraded: boolean;
}

// ajv-formats default-export interop differs across CJS/ESM resolutions.
const addFormats = ((addFormatsModule as unknown as { default?: unknown }).default ??
  addFormatsModule) as (ajv: Ajv) => void;

const ajv = new Ajv({ allErrors: true, allowUnionTypes: true });
addFormats(ajv);

function compileSafe(schema: object): ValidateFunction | null {
  try {
    return ajv.compile(schema);
  } catch {
    return null;
  }
}

const validators: Record<string, ValidateFunction | null> = {
  routing: compileSafe(routingSchema),
  requirements: compileSafe(requirementsSchema),
  taskResult: compileSafe(taskResultSchema),
  verifyEvent: compileSafe(verifyEventSchema),
  documentIndex: compileSafe(documentIndexSchema),
};

function run(name: string, data: unknown): ValidationOutcome {
  const fn = validators[name];
  if (!fn) return { valid: false, errors: [`validator '${name}' failed to compile`], degraded: true };
  try {
    const ok = fn(data);
    if (ok) return { valid: true, errors: [], degraded: false };
    const errors = (fn.errors ?? []).map((e) => `${e.instancePath || '/'} ${e.message ?? 'invalid'}`);
    return { valid: false, errors, degraded: false };
  } catch (e) {
    return { valid: false, errors: [String(e)], degraded: true };
  }
}

export const validateRouting = (d: unknown): ValidationOutcome => run('routing', d);
export const validateRequirements = (d: unknown): ValidationOutcome => run('requirements', d);
export const validateTaskResult = (d: unknown): ValidationOutcome => run('taskResult', d);
export const validateVerifyEvent = (d: unknown): ValidationOutcome => run('verifyEvent', d);
export const validateDocumentIndex = (d: unknown): ValidationOutcome => run('documentIndex', d);
