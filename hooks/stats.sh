#!/usr/bin/env bash
# cdt-stats [today|week|all]  — activity & (best-effort) cost from the SQLite state DB.
set +e

CDT_DB="${CDT_DB:-$HOME/.claude/claude-dev-team.db}"
WINDOW="${1:-week}"

if ! command -v sqlite3 >/dev/null 2>&1 && ! command -v python3 >/dev/null 2>&1; then
  echo "sqlite3 / python3 not found — analytics unavailable on this machine."; exit 0
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

# Read rows. Prefer the sqlite3 CLI; fall back to python3 (Windows / no-CLI). Output matches the CLI:
# pipe-separated columns, one row per line.
q() {
  if command -v sqlite3 >/dev/null 2>&1; then
    sqlite3 "$CDT_DB" "$1" 2>/dev/null
  elif command -v python3 >/dev/null 2>&1; then
    CDT_DB="$CDT_DB" _CDT_Q="$1" python3 -c 'import os,sqlite3
try:
    c=sqlite3.connect(os.environ["CDT_DB"])
    for row in c.execute(os.environ["_CDT_Q"]): print("|".join("" if v is None else str(v) for v in row))
    c.close()
except Exception: pass' 2>/dev/null
  fi
}

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
# Humanize a token count inline in SQL (k / M), used for the cost columns below.
_HUM="CASE WHEN %s >= 1000000 THEN printf('%%.1fM',%s/1000000.0) WHEN %s >= 1000 THEN printf('%%.1fk',%s/1000.0) ELSE CAST(%s AS TEXT) END"
hum() { printf "$_HUM" "$1" "$1" "$1" "$1" "$1"; }

echo "Tasks by tier (count · tokens):"
q "SELECT '  '||COALESCE(tier,'?')||'  ×'||COUNT(*)||'  '||$(hum "SUM(COALESCE(tokens,0))") FROM tasks WHERE started >= '$SINCE' GROUP BY tier ORDER BY tier;"
echo "Avg Task Loop iterations: $(q "SELECT IFNULL(ROUND(AVG(iterations),1),'n/a') FROM tasks WHERE started >= '$SINCE';")"
echo
echo "Agent runs — which roles cost the most (role · runs · tokens; +cache reads, discounted):"
q "SELECT '  '||REPLACE(REPLACE(agent,'claude-dev-team:',''),'cdt:','')||'  ×'||COUNT(*)||'  '||$(hum "SUM(COALESCE(tokens,0))")||'  (+'||$(hum "SUM(COALESCE(cache_read,0))")||' cache)' FROM agent_runs WHERE started >= '$SINCE' AND agent NOT IN ('unknown','') GROUP BY agent ORDER BY SUM(COALESCE(tokens,0)) DESC, COUNT(*) DESC;"
echo "Total agent tokens: $(q "SELECT $(hum "SUM(COALESCE(tokens,0))") FROM agent_runs WHERE started >= '$SINCE' AND agent NOT IN ('unknown','');")  (+ $(q "SELECT $(hum "SUM(COALESCE(cache_read,0))") FROM agent_runs WHERE started >= '$SINCE' AND agent NOT IN ('unknown','');") cache reads, discounted)"
echo
echo "Orchestration overhead (latest — orchestrator's own tokens vs the work it delegated):"
_OH="$(q "SELECT message FROM events WHERE type='orch_overhead' AND ts >= '$SINCE' ORDER BY ts DESC LIMIT 1;")"
echo "  ${_OH:-(none recorded yet — the Stop hook records main-vs-delegated tokens per session)}"
echo
echo "Token budget (your real 'cost' on Max = session + weekly rate-limit usage, NOT money):"
echo "  per-agent 'tokens' above are REAL cost-relevant tokens (input + output + cache-creation); cache"
echo "  reads are shown separately because they're heavily discounted and would otherwise swamp the ranking."
echo "  more T2/T3 tasks & agent runs = more of your budget; reserve FULL: / Opus builders for what needs it."
echo "  For exact tokens used against your limit, use Claude Code's /cost or /usage (live & authoritative)."
