#!/usr/bin/env bash
# claude-dev-team — SQLite state helper (sourced by hooks + bin scripts).
# Fail-open: every function no-ops silently if sqlite3 is missing or a query errors.

CDT_DB="${CDT_DB:-$HOME/.claude/claude-dev-team.db}"

# We can do SQLite via the sqlite3 CLI OR python3's built-in sqlite3 module — the latter makes state
# logging work on Windows / anywhere python3 is present but the CLI isn't.
_cdt_have_sqlite() { command -v sqlite3 >/dev/null 2>&1 || command -v python3 >/dev/null 2>&1; }

# Run a SQL script, swallowing all errors. Prefer the sqlite3 CLI; fall back to python3.
_cdt_sql() {
  if command -v sqlite3 >/dev/null 2>&1; then
    sqlite3 "$CDT_DB" "$1" >/dev/null 2>&1 || true
  elif command -v python3 >/dev/null 2>&1; then
    CDT_DB="$CDT_DB" _CDT_SQL="$1" python3 -c 'import os,sqlite3
try:
    c=sqlite3.connect(os.environ["CDT_DB"]); c.executescript(os.environ["_CDT_SQL"]); c.commit(); c.close()
except Exception: pass' >/dev/null 2>&1 || true
  fi
}

# Make a value safe inside a SQLite '...' string literal: double single quotes, and flatten
# newlines/CR/tabs to spaces so a value can't smear across the stored row or break log rendering.
# (SQLite does NOT process backslash escapes in '...' literals, so we must not touch '\'.)
_cdt_esc() { printf "%s" "$1" | tr '\n\r\t' '   ' | sed "s/'/''/g"; }

db_init() {
  _cdt_have_sqlite || return 0
  mkdir -p "$(dirname "$CDT_DB")" 2>/dev/null || true
  _cdt_sql "
    CREATE TABLE IF NOT EXISTS sessions(
      id TEXT, cwd TEXT, started TEXT, ended TEXT, tier TEXT, outcome TEXT);
    CREATE TABLE IF NOT EXISTS tasks(
      session_id TEXT, description TEXT, tier TEXT, status TEXT,
      iterations INTEGER, started TEXT, ended TEXT, tokens INTEGER);
    CREATE TABLE IF NOT EXISTS agent_runs(
      task_id TEXT, agent TEXT, model TEXT, started TEXT, ended TEXT, tokens INTEGER);
    CREATE TABLE IF NOT EXISTS events(
      ts TEXT, session_id TEXT, type TEXT, message TEXT);
    CREATE TABLE IF NOT EXISTS usage(
      session_id TEXT, ts TEXT, est_tokens INTEGER, est_cost REAL);
  "
  # Migrations for pre-existing DBs — each in its own call so one no-op doesn't abort the other.
  # (CREATE TABLE IF NOT EXISTS won't add a column to a table that already exists; ALTER does.
  #  The ADD COLUMN errors harmlessly if the column is already there — _cdt_sql swallows it.)
  _cdt_sql "ALTER TABLE agent_runs ADD COLUMN tokens INTEGER;"
  _cdt_sql "ALTER TABLE tasks ADD COLUMN tokens INTEGER;"
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

# db_agent <agent_type> [session_id] [tokens] — one row per dispatched subagent (from the SubagentStop
# hook). `tokens` is the real total summed from that subagent's transcript (input+output+cache), or 0.
db_agent() {
  _cdt_have_sqlite || return 0
  local ts agent sid tokens
  ts="$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null)"
  agent="$(_cdt_esc "${1:-unknown}")"; sid="$(_cdt_esc "${2:-}")"
  tokens="${3:-0}"; case "$tokens" in ''|*[!0-9]*) tokens=0 ;; esac
  _cdt_sql "INSERT INTO agent_runs(task_id,agent,model,started,ended,tokens) VALUES('$sid','$agent','','$ts','$ts',$tokens);"
}

# db_task <tier> [status] [iterations] [description] [session_id] [tokens] — one row per completed task.
db_task() {
  _cdt_have_sqlite || return 0
  local ts tier status iters desc sid tokens
  ts="$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null)"
  tier="$(_cdt_esc "${1:-?}")"; status="$(_cdt_esc "${2:-shipped}")"
  iters="${3:-0}"; case "$iters" in ''|*[!0-9]*) iters=0 ;; esac
  desc="$(_cdt_esc "${4:-}")"; sid="$(_cdt_esc "${5:-}")"
  tokens="${6:-0}"; case "$tokens" in ''|*[!0-9]*) tokens=0 ;; esac
  _cdt_sql "INSERT INTO tasks(session_id,description,tier,status,iterations,started,ended,tokens) VALUES('$sid','$desc','$tier','$status',$iters,'$ts','$ts',$tokens);"
}
