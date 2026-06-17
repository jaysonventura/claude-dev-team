#!/usr/bin/env bash
# UserPromptSubmit hook (claude-dev-team-toolkit).
# ALWAYS exits 0 — never exit 2 (exit 2 erases the user's prompt). Reads the hook payload on stdin and,
# only for non-trivial / non-sensitive / unprocessed prompts, prints an ADDITIVE additionalContext
# suggestion (the original prompt is never rewritten). All gates (sensitivity pre-gate, min length, dedupe,
# Haiku decision, length cap) live in the TypeScript engine; this shim only short-circuits cheaply.
set +e

INPUT="$(cat 2>/dev/null)"

# Recursion guard: the nested `claude --bare -p` enhancer runs with CDT_IN_ENHANCER=1.
[ "${CDT_IN_ENHANCER:-0}" = "1" ] && exit 0

CDT_HOME="$HOME/.claude"
# Global off switches (read keys directly — never `source` the env file).
_EN="$(grep -E '^CDT_ENABLED=' "$CDT_HOME/claude-dev-team.env" 2>/dev/null | head -1 | cut -d= -f2-)"
[ "$_EN" = "0" ] && exit 0
_PE="$(grep -E '^CDT_PROMPT_ENHANCE=' "$CDT_HOME/claude-dev-team.env" 2>/dev/null | head -1 | cut -d= -f2-)"
case "$_PE" in 0|false|off) exit 0 ;; esac

command -v node >/dev/null 2>&1 || exit 0
TKDIST="$(cd "$(dirname "$0")/../toolkit/dist" 2>/dev/null && pwd)"
[ -n "$TKDIST" ] && [ -f "$TKDIST/cli/hook.js" ] || exit 0

# The engine prints the UserPromptSubmit additionalContext JSON (or nothing). Pass it through verbatim.
# Do NOT set CDT_IN_ENHANCER here — only the nested claude call sets it.
printf '%s' "$INPUT" | node "$TKDIST/cli/hook.js" prompt 2>/dev/null

exit 0
