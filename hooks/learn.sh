#!/usr/bin/env bash
# cdt-learn "<lesson>" [area] — append a durable lesson to the vault so cdt-recall / cdt-advise surface
# it on relevant future tasks. The lesson is written to markdown (never sourced), so it's data, not code.
set +e

LESSON="$1"; AREA="$2"
[ -z "$LESSON" ] && { echo "usage: cdt-learn \"<lesson>\" [area]"; exit 0; }

VAULT="${CDT_VAULT:-$HOME/.claude/vault}"
mkdir -p "$VAULT" 2>/dev/null
LEARN="$VAULT/learnings.md"
[ -f "$LEARN" ] || printf '# Learnings\n\nDurable lessons the orchestrator recalls across sessions.\n\n' > "$LEARN"

DATE="$(date +%Y-%m-%d 2>/dev/null)"
CLEAN="$(printf '%s' "$LESSON" | tr '\n\r\t' '   ')"                 # one lesson per line
PREFIX=""
[ -n "$AREA" ] && PREFIX="$(printf '%s' "$AREA" | tr -cd 'A-Za-z0-9 _-')"": "

printf -- '- [%s] %s%s\n' "$DATE" "$PREFIX" "$CLEAN" >> "$LEARN"
echo "learned → - [$DATE] ${PREFIX}${CLEAN}"
echo "(cdt-recall will surface it on relevant future tasks)"
exit 0
