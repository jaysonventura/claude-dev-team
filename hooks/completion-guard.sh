#!/usr/bin/env bash
# Stop hook: when a session that made edits ends, record a session row + status digest (silent),
# and OPTIONALLY remind once to run the completion mandate (opt-in, off by default to stay cheap).
# Loop-guarded via stop_hook_active. Fail-open: always exits cleanly.
set +e

INPUT="$(cat 2>/dev/null)"

# Loop guard: if this stop was itself triggered by a stop hook, do nothing.
printf '%s' "$INPUT" | grep -q '"stop_hook_active"[[:space:]]*:[[:space:]]*true' && exit 0

get() { printf '%s' "$INPUT" | sed -n "s/.*\"$1\"[[:space:]]*:[[:space:]]*\"\([^\"]*\)\".*/\1/p" | head -1; }
SESSION_ID="$(get session_id)"
CWD="$(get cwd)"; [ -z "$CWD" ] && CWD="$PWD"
TRANSCRIPT="$(get transcript_path)"

MARK="${TMPDIR:-/tmp}/cdt-edits-${SESSION_ID:-default}.marker"
REMIND_MARK="${TMPDIR:-/tmp}/cdt-reminded-${SESSION_ID:-default}.marker"

# No edits this session → stay completely silent.
[ -f "$MARK" ] || exit 0

# Silent bookkeeping: record a session row in the DB.
CDT_HOME="$HOME/.claude"
[ -f "$CDT_HOME/bin/cdt-db.sh" ] && . "$CDT_HOME/bin/cdt-db.sh" 2>/dev/null && \
  db_session "${SESSION_ID:-unknown}" "$CWD" "stopped" 2>/dev/null

# A disabled CDT never gates or reminds (behaves as stock Claude Code).
_EN="$(grep -E '^CDT_ENABLED=' "$CDT_HOME/claude-dev-team.env" 2>/dev/null | head -1 | cut -d= -f2-)"
[ "$_EN" = "0" ] && exit 0

# --- Verification gate: edits happened — require that a test/build/lint/typecheck ran afterward. -------
# Default ON (block). Soften any time:  cdt-config verify warn|off  (writes CDT_VERIFY_GATE).
GATE="$(grep -E '^CDT_VERIFY_GATE=' "$CDT_HOME/claude-dev-team.env" 2>/dev/null | head -1 | cut -d= -f2-)"
case "$GATE" in block|warn|off) : ;; *) GATE=block ;; esac

# Docs-only exemption (claude-dev-team-toolkit): a session whose edits are ALL plan/markdown docs needs no
# verifying command — treat as verification:not_run, never a blocking failure. File-scope aware; NOT a global
# "verify off". Toggle with CDT_VERIFY_DOCS_EXEMPT=0.
_DOCS_EXEMPT="$(grep -E '^CDT_VERIFY_DOCS_EXEMPT=' "$CDT_HOME/claude-dev-team.env" 2>/dev/null | head -1 | cut -d= -f2-)"
case "$_DOCS_EXEMPT" in 0|false|off) _DOCS_EXEMPT=0 ;; *) _DOCS_EXEMPT=1 ;; esac
_DOCS_ONLY=0
if [ "$_DOCS_EXEMPT" = 1 ] && command -v git >/dev/null 2>&1; then
  _CHANGED="$( { git -C "$CWD" diff --name-only HEAD 2>/dev/null; git -C "$CWD" ls-files --others --exclude-standard 2>/dev/null; } )"
  if [ -n "$_CHANGED" ]; then
    _DOCS_ONLY=1
    while IFS= read -r _f; do
      [ -z "$_f" ] && continue
      case "$_f" in
        *.claude/plans/*|*.md|*.markdown) : ;;
        *) _DOCS_ONLY=0; break ;;
      esac
    done <<EOF_DOCS
$_CHANGED
EOF_DOCS
  fi
fi
[ "$_DOCS_ONLY" = 1 ] && db_event verify_gate "docs-exempt" "${SESSION_ID:-}" 2>/dev/null

if [ "$GATE" != "off" ] && [ "$_DOCS_ONLY" != 1 ]; then
  GHOOKS="$(cd "$(dirname "$0")" 2>/dev/null && pwd)"
  # shellcheck source=/dev/null
  . "$GHOOKS/verify-lib.sh" 2>/dev/null
  VMARK="$(cdt_verify_marker "${SESSION_ID:-default}" 2>/dev/null)"
  VBLOCK="${TMPDIR:-/tmp}/cdt-verify-blocked-${SESSION_ID:-default}.marker"

  unverified=1
  # Verified iff a verify-marker exists and the edit-marker is NOT newer than it (tie -> verified).
  [ -n "$VMARK" ] && [ -f "$VMARK" ] && [ ! "$MARK" -nt "$VMARK" ] && unverified=0
  # Rescue: a verifying command in the MAIN transcript that didn't trip the marker (keep false-positives low).
  if [ "$unverified" = 1 ] && [ -n "$TRANSCRIPT" ] && cdt_verify_scan_transcript "$TRANSCRIPT" 2>/dev/null; then
    unverified=0
  fi

  if [ "$unverified" = 0 ]; then
    db_event verify_gate "pass" "${SESSION_ID:-}" 2>/dev/null
  elif [ ! -f "$VBLOCK" ]; then
    : > "$VBLOCK" 2>/dev/null   # fire at most once per session — never trap the user in a loop
    if [ "$GATE" = "warn" ]; then
      db_event verify_gate "warn" "${SESSION_ID:-}" 2>/dev/null
      echo "claude-dev-team: ⚠ edits were made but no test/build/lint/typecheck command ran afterward — verify before trusting this as done (cdt-config verify off to silence)." >&2
    else
      db_event verify_gate "block" "${SESSION_ID:-}" 2>/dev/null
      printf '{"decision":"block","reason":"%s"}\n' "claude-dev-team: edits were made but no verifying command (test / build / lint / typecheck) ran afterward. Run the project's verifying command and paste its output before finishing. If a subagent already ran it, paste that output and stop again. (Soften: cdt-config verify warn|off.)"
      exit 0
    fi
  fi
fi

# --- Scope gate: surface contract overreach/collision flagged by SubagentStop this session. -----------
# Default WARN (more moving parts than the verify gate). Tune: cdt-config scope warn|block|off.
SCOPEGATE="$(grep -E '^CDT_SCOPE_GATE=' "$CDT_HOME/claude-dev-team.env" 2>/dev/null | head -1 | cut -d= -f2-)"
case "$SCOPEGATE" in block|warn|off) : ;; *) SCOPEGATE=warn ;; esac
FINDINGS="$CDT_HOME/.cdt/contracts/${SESSION_ID:-default}/findings.jsonl"
SBLOCK="${TMPDIR:-/tmp}/cdt-scope-blocked-${SESSION_ID:-default}.marker"
if [ "$SCOPEGATE" != "off" ] && [ -s "$FINDINGS" ] && [ ! -f "$SBLOCK" ]; then
  : > "$SBLOCK" 2>/dev/null   # fire at most once per session
  SN="$(grep -c '"type"' "$FINDINGS" 2>/dev/null)"; case "$SN" in ''|*[!0-9]*) SN=0 ;; esac
  if [ "$SCOPEGATE" = "warn" ]; then
    db_event scope_gate "warn ($SN)" "${SESSION_ID:-}" 2>/dev/null
    echo "claude-dev-team: ⚠ $SN scope finding(s) this session — an agent wrote outside its exclusive contract (review: cdt-contract findings)." >&2
  else
    db_event scope_gate "block ($SN)" "${SESSION_ID:-}" 2>/dev/null
    printf '{"decision":"block","reason":"%s"}\n' "claude-dev-team: $SN agent scope violation(s) this session — a subagent wrote files outside its exclusive contract or into a peer's scope. Review them (run: cdt-contract findings), reconcile, then stop. (Soften: cdt-config scope warn|off.)"
    exit 0
  fi
fi

# --- Memory gate: a substantial (team-tier) session that edited files should persist a vault lesson. ---
# Only fires when the session dispatched >=1 specialist (T0/T1 solo work is exempt). Default WARN.
MEMGATE="$(grep -E '^CDT_MEMORY_GATE=' "$CDT_HOME/claude-dev-team.env" 2>/dev/null | head -1 | cut -d= -f2-)"
case "$MEMGATE" in block|warn|off) : ;; *) MEMGATE=warn ;; esac
MBLOCK="${TMPDIR:-/tmp}/cdt-memory-blocked-${SESSION_ID:-default}.marker"
if [ "$MEMGATE" != "off" ] && [ ! -f "$MBLOCK" ]; then
  _NAG=0
  if command -v python3 >/dev/null 2>&1 && [ -f "$CDT_HOME/claude-dev-team.db" ]; then
    _NAG="$(CDT_DB="$CDT_HOME/claude-dev-team.db" CDT_SID="${SESSION_ID:-}" python3 -c 'import os,sqlite3
try: print(sqlite3.connect(os.environ["CDT_DB"]).execute("SELECT count(*) FROM agent_runs WHERE task_id=?",(os.environ.get("CDT_SID",""),)).fetchone()[0])
except Exception: print(0)' 2>/dev/null)"
  fi
  case "$_NAG" in ''|*[!0-9]*) _NAG=0 ;; esac
  if [ "$_NAG" -gt 0 ]; then
    LEARNF="$CDT_HOME/vault/learnings.md"
    # "persisted a lesson" iff learnings.md is at least as new as the edit-marker (tie -> learned).
    if [ ! -f "$LEARNF" ] || [ "$MARK" -nt "$LEARNF" ]; then
      : > "$MBLOCK" 2>/dev/null
      if [ "$MEMGATE" = "warn" ]; then
        db_event memory_gate "warn" "${SESSION_ID:-}" 2>/dev/null
        echo "claude-dev-team: ⚠ team-tier session — capture a durable lesson before finishing: cdt-learn \"<lesson>\" (or cdt-config memory off)." >&2
      else
        db_event memory_gate "block" "${SESSION_ID:-}" 2>/dev/null
        printf '{"decision":"block","reason":"%s"}\n' "claude-dev-team: this session dispatched specialists and edited files but recorded no vault lesson. Capture what was non-obvious so it's not relearned: cdt-learn \"<lesson>\". (Soften: cdt-config memory warn|off.) Then stop."
        exit 0
      fi
    else
      db_event memory_gate "pass" "${SESSION_ID:-}" 2>/dev/null
    fi
  fi
fi

# --- Orchestrator overhead: how much the orchestration layer itself cost vs the work it delegated. -----
if [ -n "$TRANSCRIPT" ] && [ -f "$TRANSCRIPT" ] && command -v python3 >/dev/null 2>&1; then
  _UH="$(cd "$(dirname "$0")" 2>/dev/null && pwd)"
  if [ -f "$_UH/usage-lib.sh" ]; then
    # shellcheck source=/dev/null
    . "$_UH/usage-lib.sh" 2>/dev/null
    read -r _MAIN _ <<EOF4
$(cdt_usage_tokens "$TRANSCRIPT")
EOF4
    case "$_MAIN" in ''|*[!0-9]*) _MAIN=0 ;; esac
    if [ "${_MAIN:-0}" -gt 0 ]; then
      _AGG="$(CDT_DB="$CDT_HOME/claude-dev-team.db" CDT_SID="${SESSION_ID:-}" python3 -c 'import os,sqlite3
try: print(sqlite3.connect(os.environ["CDT_DB"]).execute("SELECT COALESCE(SUM(tokens),0) FROM agent_runs WHERE task_id=?",(os.environ.get("CDT_SID",""),)).fetchone()[0])
except Exception: print(0)' 2>/dev/null)"
      case "$_AGG" in ''|*[!0-9]*) _AGG=0 ;; esac
      db_event orch_overhead "main=$_MAIN delegated=$_AGG" "${SESSION_ID:-}" 2>/dev/null
    fi
  fi
fi

# --- TASK_RESULT finalize (claude-dev-team-toolkit) — local only, NO notification. -------------------
# Writes .claude/TASK_RESULT.json with verification derived strictly from verify-events.jsonl, then surfaces
# (on stderr, non-blocking) the staging guard + a cdt-verify nudge. Never blocks (block-once is preserved).
_TKDIST="$(cd "$(dirname "$0")/../toolkit/dist" 2>/dev/null && pwd)"
if [ -n "$_TKDIST" ] && [ -f "$_TKDIST/cli/hook.js" ] && command -v node >/dev/null 2>&1; then
  _FIN="$(printf '%s' "$INPUT" | node "$_TKDIST/cli/hook.js" finalize 2>/dev/null)"
  if [ -n "$_FIN" ] && command -v python3 >/dev/null 2>&1; then
    # Fire the 6-field final-response reminder at most ONCE per session (stderr, never blocks → no loop).
    FRMARK="${TMPDIR:-/tmp}/cdt-finalresp-${SESSION_ID:-default}.marker"
    _FR=0; [ ! -f "$FRMARK" ] && { : > "$FRMARK" 2>/dev/null; _FR=1; }
    CDT_FIN="$_FIN" CDT_FR="$_FR" python3 - 1>&2 <<'PYF' 2>/dev/null || true
import os, json
try:
    d = json.loads(os.environ.get("CDT_FIN", "{}"))
except Exception:
    d = {}
for w in (d.get("stagingWarnings") or []):
    print("claude-dev-team: ⚠ STAGING GUARD: " + str(w))
if d.get("hookOnly"):
    print("claude-dev-team: a verify command ran but not via cdt-verify — re-run as 'cdt-verify -- <cmd>' to record trusted evidence.")
# TASK_RESULT.json is the machine source of truth (already written by the engine). This is a one-shot,
# non-blocking nudge so the final reply matches the recorded result — it never blocks or loops.
if os.environ.get("CDT_FR") == "1" and d.get("finalResponse"):
    print("claude-dev-team: TASK_RESULT.json written (verification=%s). Format your final reply as:" % d.get("verification"))
    print(d["finalResponse"])
PYF
  fi
fi

# Optional mandate reminder — opt in with CDT_STOP_REMINDER=1 (kept off by default for cost).
# Read just this key (don't `source` the env file — a crafted value must never execute).
_REMIND="$(grep -E '^CDT_STOP_REMINDER=' "$CDT_HOME/claude-dev-team.env" 2>/dev/null | head -1 | cut -d= -f2-)"
if [ "${_REMIND:-0}" = "1" ] && [ ! -f "$REMIND_MARK" ]; then
  : > "$REMIND_MARK" 2>/dev/null
  printf '{"decision":"block","reason":"%s"}\n' \
    "claude-dev-team: edits were made — run the completion mandate before finishing (simplify, code-review, reuse-audit, dead-code scan, verify with command output, persist a vault learning), then post a SHIP digest via cdt-notify. If already done, you may stop."
  exit 0
fi
exit 0
