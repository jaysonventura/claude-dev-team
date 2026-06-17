// JSON Schemas (as TS objects so they compile into dist/ and need no JSON-copy step).

export const verifyEventSchema = {
  $id: 'cdt:verify-event',
  type: 'object',
  required: ['ts', 'command', 'type', 'exitCode', 'cwd', 'source'],
  additionalProperties: false,
  properties: {
    ts: { type: 'string' },
    command: { type: 'string' },
    type: { enum: ['test', 'build', 'lint', 'typecheck', 'other'] },
    exitCode: { type: ['integer', 'null'] },
    cwd: { type: 'string' },
    source: { enum: ['cdt-verify', 'hook'] },
  },
} as const;

export const taskResultSchema = {
  $id: 'cdt:task-result',
  type: 'object',
  required: ['status', 'task', 'result', 'verification', 'artifact', 'nextStep'],
  additionalProperties: false,
  properties: {
    status: { enum: ['done', 'partial', 'blocked', 'failed', 'needs_review'] },
    task: { type: 'string' },
    result: { type: 'string' },
    verification: { enum: ['passed', 'failed', 'not_run'] },
    artifact: { type: ['string', 'null'] },
    nextStep: { type: 'string' },
  },
} as const;

export const routingSchema = {
  $id: 'cdt:routing',
  type: 'object',
  required: [
    'version',
    'generatedAt',
    'promptRedacted',
    'promptHash',
    'tier',
    'model',
    'confidence',
    'advisory',
    'enhanced',
    'degraded',
    'risk',
    'securityReview',
    'agents',
    'gates',
    'safety',
    'notes',
  ],
  additionalProperties: false,
  properties: {
    version: { type: 'string' },
    generatedAt: { type: 'string' },
    promptRedacted: { type: 'string' },
    promptHash: { type: 'string' },
    tier: { enum: ['T0', 'T1', 'T2', 'T3'] },
    model: { enum: ['haiku', 'sonnet', 'opus'] },
    confidence: { type: 'number', minimum: 0, maximum: 1 },
    advisory: { const: true },
    enhanced: { type: 'boolean' },
    degraded: { type: 'boolean' },
    risk: {
      type: 'object',
      required: ['flagged', 'domains', 'floor'],
      additionalProperties: false,
      properties: {
        flagged: { type: 'boolean' },
        domains: { type: 'array', items: { type: 'string' } },
        floor: { enum: ['T0', 'T1', 'T2', 'T3', 'none'] },
      },
    },
    securityReview: { type: 'boolean' },
    agents: {
      type: 'array',
      items: {
        type: 'object',
        required: ['name', 'owns', 'reason'],
        additionalProperties: false,
        properties: {
          name: { type: 'string' },
          owns: { type: 'array', items: { type: 'string' } },
          reason: { type: 'string' },
        },
      },
    },
    gates: { type: 'array', items: { type: 'string' } },
    safety: {
      type: 'object',
      required: ['findings'],
      additionalProperties: false,
      properties: {
        findings: {
          type: 'array',
          items: {
            type: 'object',
            required: ['domain', 'severity', 'match', 'evidenceRedacted'],
            additionalProperties: false,
            properties: {
              domain: { type: 'string' },
              severity: { enum: ['low', 'medium', 'high'] },
              match: { type: 'string' },
              evidenceRedacted: { type: 'string' },
            },
          },
        },
      },
    },
    notes: { type: 'string' },
  },
} as const;

export const requirementsSchema = {
  $id: 'cdt:requirements',
  type: 'object',
  required: ['version', 'generatedAt', 'documents', 'requirements'],
  additionalProperties: false,
  properties: {
    version: { type: 'string' },
    generatedAt: { type: 'string' },
    documents: { type: 'array', items: { type: 'string' } },
    requirements: {
      type: 'array',
      items: {
        type: 'object',
        // `source` is REQUIRED — a requirement without a source reference is rejected.
        required: ['id', 'text', 'type', 'priority', 'source', 'status'],
        additionalProperties: false,
        properties: {
          id: { type: 'string' },
          text: { type: 'string' },
          type: { enum: ['functional', 'nonfunctional', 'constraint', 'assumption'] },
          priority: { enum: ['must', 'should', 'could', 'wont'] },
          source: {
            type: 'object',
            required: ['doc'],
            additionalProperties: false,
            properties: {
              doc: { type: 'string' },
              page: { type: ['integer', 'null'] },
              line: { type: ['integer', 'null'] },
              anchor: { type: ['string', 'null'] },
            },
          },
          tags: { type: 'array', items: { type: 'string' } },
          risk: { type: 'array', items: { type: 'string' } },
          sensitivity: { type: 'array', items: { type: 'string' } },
          status: { enum: ['extracted', 'needs_review'] },
        },
      },
    },
  },
} as const;

export const documentIndexSchema = {
  $id: 'cdt:document-index',
  type: 'object',
  required: ['documents'],
  additionalProperties: false,
  properties: {
    documents: {
      type: 'array',
      items: {
        type: 'object',
        required: ['path', 'type', 'chars', 'sections', 'rawTextAnchor', 'sensitivity'],
        additionalProperties: false,
        properties: {
          path: { type: 'string' },
          type: { type: 'string' },
          chars: { type: 'integer' },
          pages: { type: ['integer', 'null'] },
          sections: {
            type: 'array',
            items: {
              type: 'object',
              required: ['heading', 'startLine', 'endLine'],
              additionalProperties: false,
              properties: {
                heading: { type: 'string' },
                startLine: { type: 'integer' },
                endLine: { type: 'integer' },
              },
            },
          },
          rawTextAnchor: { type: 'string' },
          sensitivity: { type: 'array', items: { type: 'string' } },
          ocrConfidence: { type: ['number', 'null'] },
        },
      },
    },
  },
} as const;
