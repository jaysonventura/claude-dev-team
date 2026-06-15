#!/usr/bin/env bash
# claude-dev-team — SQLite state helper (sourced by hooks + bin scripts).
# Fail-open: every function no-ops silently if sqlite3 is missing or a query errors.

CDT_DB="${CDT_DB:-$HOME/.claude/claude-dev-team.db}"

_cdt_have_sqlite() { command -v sqlite3 >/dev/null 2>&1; }

# Run a SQL statement, swallowing all errors.
_cdt_sql() {
  _cdt_have_sqlite || return 0
  sqlite3 "$CDT_DB" "$1" >/dev/null 2>&1 || true
}

# Escape single quotes for SQL string literals.
_cdt_esc() { printf "%s" "$1" | sed "s/'/''/g"; }

db_init() {
  _cdt_have_sqlite || return 0
  mkdir -p "$(dirname "$CDT_DB")" 2>/dev/null || true
  _cdt_sql "
    CREATE TABLE IF NOT EXISTS sessions(
      id TEXT, cwd TEXT, started TEXT, ended TEXT, tier TEXT, outcome TEXT);
    CREATE TABLE IF NOT EXISTS tasks(
      session_id TEXT, description TEXT, tier TEXT, status TEXT,
      iterations INTEGER, started TEXT, ended TEXT);
    CREATE TABLE IF NOT EXISTS agent_runs(
      task_id TEXT, agent TEXT, model TEXT, started TEXT, ended TEXT);
    CREATE TABLE IF NOT EXISTS events(
      ts TEXT, session_id TEXT, type TEXT, message TEXT);
    CREATE TABLE IF NOT EXISTS usage(
      session_id TEXT, ts TEXT, est_tokens INTEGER, est_cost REAL);
  "
}

# db_event <type> <message> [session_id]
db_event() {
  _cdt_have_sqlite || return 0
  local ts type msg sid
  ts="$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null)"
  type="$(_cdt_esc "$1")"; msg="$(_cdt_esc "$2")"; sid="$(_cdt_esc "${3:-}")"
  _cdt_sql "INSERT INTO events(ts,session_id,type,message) VALUES('$ts','$sid','$type','$msg');"
}

# db_session <id> <cwd> <outcome>
db_session() {
  _cdt_have_sqlite || return 0
  local ts id cwd outcome
  ts="$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null)"
  id="$(_cdt_esc "$1")"; cwd="$(_cdt_esc "$2")"; outcome="$(_cdt_esc "${3:-}")"
  _cdt_sql "INSERT INTO sessions(id,cwd,started,ended,outcome) VALUES('$id','$cwd','$ts','$ts','$outcome');"
}
