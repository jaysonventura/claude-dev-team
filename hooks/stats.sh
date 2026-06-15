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
echo "Avg Task Loop iterations: $(q "SELECT IFNULL(ROUND(AVG(iterations),1),'n/a') FROM tasks WHERE started >= '$SINCE';")"
echo
echo "Agent runs (by role):"
q "SELECT '  '||REPLACE(agent,'claude-dev-team:','')||'  '||COUNT(*) FROM agent_runs WHERE started >= '$SINCE' AND agent NOT IN ('unknown','') GROUP BY agent ORDER BY COUNT(*) DESC;"
echo
echo "Token budget (your real 'cost' on Max = session + weekly rate-limit usage, NOT money):"
echo "  the activity above is what consumes your token budget — more T2/T3 tasks & agent runs = more tokens."
echo "  For exact tokens used against your limit, use Claude Code's /cost or /usage (live & accurate)."
