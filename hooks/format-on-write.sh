#!/usr/bin/env bash
# PostToolUse (Edit|Write|MultiEdit) hook:
#  - marks that edits happened this session (for the Stop digest)
#  - runs the project's prettier ONLY if locally installed AND configured (never downloads, never blocks)
# Fail-open: always exit 0.
set +e

INPUT="$(cat 2>/dev/null)"

# Extract fields best-effort (no jq dependency).
get() { printf '%s' "$INPUT" | sed -n "s/.*\"$1\"[[:space:]]*:[[:space:]]*\"\([^\"]*\)\".*/\1/p" | head -1; }
SESSION_ID="$(get session_id)"
FILE="$(get file_path)"
CWD="$(get cwd)"
[ -z "$CWD" ] && CWD="$PWD"

# 1) Edits marker for this session (used by the Stop guard).
MARK="${TMPDIR:-/tmp}/cdt-edits-${SESSION_ID:-default}.marker"
: > "$MARK" 2>/dev/null

# 2) Guarded format. Only act when there's a real file, a local prettier, and a prettier config.
[ -n "$FILE" ] && [ -f "$FILE" ] || exit 0
command -v npx >/dev/null 2>&1 || exit 0

# Look for a prettier config from the file's dir upward to cwd.
has_prettier_config() {
  local dir; dir="$(cd "$(dirname "$FILE")" 2>/dev/null && pwd)"
  while [ -n "$dir" ] && [ "$dir" != "/" ]; do
    for c in .prettierrc .prettierrc.json .prettierrc.js .prettierrc.cjs .prettierrc.yaml .prettierrc.yml prettier.config.js prettier.config.cjs; do
      [ -f "$dir/$c" ] && return 0
    done
    [ -f "$dir/package.json" ] && grep -q '"prettier"' "$dir/package.json" 2>/dev/null && return 0
    [ "$dir" = "$CWD" ] && break
    dir="$(dirname "$dir")"
  done
  return 1
}

if has_prettier_config; then
  # --no-install: use only a locally installed prettier; never fetch from the network.
  ( cd "$CWD" 2>/dev/null && npx --no-install prettier --write "$FILE" >/dev/null 2>&1 ) || true
fi
exit 0
