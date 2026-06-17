// Shared instruction text for the enhancer backends. The enhancer only RESTATES the task more clearly;
// it must never invent facts or use tools.

export const ENHANCE_SYSTEM = 'Return ONLY the rewritten prompt. No preamble, no commentary, no tools.';

export function buildEnhanceUserPrompt(prompt: string): string {
  return (
    'Rewrite the following software task as a single, clear, specific engineering prompt. ' +
    'Preserve the original intent exactly; do not add facts, scope, or assumptions that are not present. ' +
    'If something is ambiguous, note it as an open question rather than inventing an answer.\n\n' +
    `TASK:\n${prompt.trim()}`
  );
}
