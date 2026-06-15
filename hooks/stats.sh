#!/usr/bin/env bash
# cdt-stats [today|week|all]  — activity & (best-effort) cost from the SQLite state DB.
set +e

CDT_DB="${CDT_DB:-$HOME/.claude/claude-dev-team.db}"
WINDOW="${1:-week}"

if ! command -v sqlite3 >/dev/null 2>&1; then
  echo "sqlite3 not found — analytics unavailable on this machine."; exit 0
fi
if [ ! -f "$CDT_DB" ]; then
  echo "No data yet ($CDT_DB). It populates as you complete tasks."; exit 0
fi

case "$WINDOW" in
  today) SINCE="$(date -u +%Y-%m-%dT00:00:00Z 2>/dev/null)" ;;
  all)   SINCE="0000" ;;
  *)     WINDOW="week"; SINCE="$(date -u -v-7d +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -d '7 days ago' +%Y-%m-%dT%H:%M:%SZ 2>/dev/null)" ;;
esac
[ -z "$SINCE" ] && SINCE="0000"

q() { sqlite3 "$CDT_DB" "$1" 2>/dev/null; }

echo "=== claude-dev-team stats ($WINDOW, since $SINCE) ==="
echo
echo "Sessions     : $(q "SELECT COUNT(*) FROM sessions WHERE started >= '$SINCE';")"
echo "Events       : $(q "SELECT COUNT(*) FROM events WHERE ts >= '$SINCE';")"
echo
echo "Events by type:"
q "SELECT '  '||type||'  '||COUNT(*) FROM events WHERE ts >= '$SINCE' GROUP BY type ORDER BY COUNT(*) DESC;"
echo
echo "Blockers/Deferred:"
q "SELECT '  '||type||'  '||COUNT(*) FROM events WHERE ts >= '$SINCE' AND type IN ('BLOCKER','DEFERRED') GROUP BY type;"
echo
echo "Tasks by tier:"
q "SELECT '  '||COALESCE(tier,'?')||'  '||COUNT(*) FROM tasks WHERE started >= '$SINCE' GROUP BY tier;"
echo
echo "Agent runs:"
q "SELECT '  '||agent||'  '||COUNT(*) FROM agent_runs WHERE started >= '$SINCE' GROUP BY agent ORDER BY COUNT(*) DESC;"
echo
# Best-effort cost note from Claude Code's own usage cache (labeled estimate).
CACHE="$HOME/.claude/stats-cache.json"
if [ -f "$CACHE" ]; then
  echo "Cost: see Claude Code usage (~/.claude/stats-cache.json) — token/cost figures are an estimate."
else
  echo "Cost: estimate unavailable (no usage cache found)."
fi
