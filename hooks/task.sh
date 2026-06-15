#!/usr/bin/env bash
# cdt-task <tier> [status] [iterations] [description]
# Record a completed task (tier + Task Loop iterations) for /stats. Called by the orchestrator at ship.
# Fail-open.
set +e

CDT_HOME="$HOME/.claude"
DB_LIB="$CDT_HOME/bin/cdt-db.sh"
[ -f "$DB_LIB" ] || DB_LIB="$(cd "$(dirname "$0")" 2>/dev/null && pwd)/db.sh"
# shellcheck source=/dev/null
[ -f "$DB_LIB" ] && . "$DB_LIB" 2>/dev/null && db_task "$1" "$2" "$3" "$4" "${CLAUDE_SESSION_ID:-}"

echo "logged task: tier=${1:-?} status=${2:-shipped} iterations=${3:-0}"
