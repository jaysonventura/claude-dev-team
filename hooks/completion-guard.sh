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

# --- Trusted verdict (toolkit) --------------------------------------------------------------------
# The engine derives verification STRICTLY from .claude/runtime/verify-events.jsonl, where only
# `cdt-verify -- <cmd>` writes a real exit code. CDT_EDIT_SINCE floors it at the last edit, so a green run
# from before the change cannot vouch for the code that replaced it.
_TK_ON="$(grep -E '^CDT_TOOLKIT_ENABLED=' "$CDT_HOME/claude-dev-team.env" 2>/dev/null | head -1 | cut -d= -f2-)"
_TKDIST="$(cd "$(dirname "$0")/../toolkit/dist" 2>/dev/null && pwd)"
case "$_TK_ON" in 0|false|off) _TKDIST="" ;; esac
_FIN=""; _VERIF=""; _FAILING=""
if [ -n "$_TKDIST" ] && [ -f "$_TKDIST/cli/hook.js" ] && command -v node >/dev/null 2>&1; then
  _SINCE=""
  if [ -f "$MARK" ] && command -v python3 >/dev/null 2>&1; then
    _SINCE="$(CDT_M="$MARK" python3 -c 'import os,datetime
print(datetime.datetime.utcfromtimestamp(os.path.getmtime(os.environ["CDT_M"])).strftime("%Y-%m-%dT%H:%M:%SZ"))' 2>/dev/null)"
  fi
  _FIN="$(printf '%s' "$INPUT" | CDT_EDIT_SINCE="$_SINCE" node "$_TKDIST/cli/hook.js" finalize 2>/dev/null)"
  if [ -n "$_FIN" ] && command -v python3 >/dev/null 2>&1; then
    _VERIF="$(CDT_FIN="$_FIN" python3 -c 'import os,json
try: print(json.loads(os.environ["CDT_FIN"]).get("verification") or "")
except Exception: pass' 2>/dev/null)"
    _FAILING="$(CDT_FIN="$_FIN" python3 -c 'import os,json
try: d=json.loads(os.environ["CDT_FIN"])
except Exception: raise SystemExit
for f in (d.get("failing") or []): print("%s (exit %s)" % (f.get("command",""), f.get("exitCode")))' 2>/dev/null)"
  fi
fi

# --- Verification gate + TASK LOOP -----------------------------------------------------------------
# Two failures this replaces. (1) The old gate accepted "a verifying command RAN": it matched the command
# string, so a red `npm test` satisfied it exactly as well as a green one — the mechanism behind sessions
# that end on "done" with failing tests. (2) It fired at most ONCE per session, so a genuine failure got a
# single nudge and then the session was free to end. Now the verdict comes from real exit codes, and a RED
# verdict blocks repeatedly until it goes green or the iteration cap is hit.
if [ "$GATE" != "off" ] && [ "$_DOCS_ONLY" != 1 ]; then
  GHOOKS="$(cd "$(dirname "$0")" 2>/dev/null && pwd)"
  # shellcheck source=/dev/null
  . "$GHOOKS/verify-lib.sh" 2>/dev/null
  LOOPSTATE="${TMPDIR:-/tmp}/cdt-loop-${SESSION_ID:-default}.state"
  VBLOCK="${TMPDIR:-/tmp}/cdt-verify-blocked-${SESSION_ID:-default}.marker"

  _MAXIT="$(grep -E '^CDT_MAX_ITERATIONS=' "$CDT_HOME/claude-dev-team.env" 2>/dev/null | head -1 | cut -d= -f2-)"
  case "$_MAXIT" in ''|*[!0-9]*) _MAXIT=5 ;; esac

  # Iteration + signature state: "<count>\n<signature>". The signature is the set of currently-red commands;
  # seeing the SAME one twice means the last fix attempt changed nothing, which is the Bug Council trigger.
  _IT=0; _PREVSIG=""
  if [ -f "$LOOPSTATE" ]; then
    _IT="$(sed -n 1p "$LOOPSTATE" 2>/dev/null)"; case "$_IT" in ''|*[!0-9]*) _IT=0 ;; esac
    _PREVSIG="$(sed -n 2p "$LOOPSTATE" 2>/dev/null)"
  fi
  _SIG="$(printf '%s' "$_FAILING" | sort | cksum 2>/dev/null | tr -d ' \n')"

  if [ "$_VERIF" = "failed" ]; then
    # ---- RED: loop until green, bounded. -----------------------------------------------------------
    _IT=$((_IT + 1))
    printf '%s\n%s\n' "$_IT" "$_SIG" > "$LOOPSTATE" 2>/dev/null
    _ESC=""
    [ -n "$_PREVSIG" ] && [ "$_PREVSIG" = "$_SIG" ] && \
      _ESC=" The SAME command(s) failed identically last iteration — the last fix changed nothing. Stop patching and diagnose: run /cdt:bug-council for a root-cause verdict before editing again."
    if [ "$_IT" -gt "$_MAXIT" ]; then
      # Cap reached. Stop blocking (never trap a session forever) but forbid a success claim: the P3 gate
      # below reads this marker and blocks any "done/fixed/passing" wording while the evidence is red.
      : > "${TMPDIR:-/tmp}/cdt-loop-exhausted-${SESSION_ID:-default}.marker" 2>/dev/null
      db_event verify_gate "loop-cap ($_IT)" "${SESSION_ID:-}" 2>/dev/null
      echo "claude-dev-team: ⚠ verification still FAILING after $_MAXIT iterations — reporting as BLOCKER, not done. Red: $(printf '%s' "$_FAILING" | tr '\n' ';')" >&2
    elif [ "$GATE" = "warn" ]; then
      db_event verify_gate "warn-failed" "${SESSION_ID:-}" 2>/dev/null
      echo "claude-dev-team: ⚠ verification FAILED — $(printf '%s' "$_FAILING" | tr '\n' ';') (cdt-config verify block to enforce)" >&2
    else
      db_event verify_gate "block-failed ($_IT)" "${SESSION_ID:-}" 2>/dev/null
      _REASON="claude-dev-team: VERIFICATION FAILED — this is not done. Currently red: $(printf '%s' "$_FAILING" | tr '\n' ';' | sed 's/"/\\"/g'). Task Loop iteration $_IT/$_MAXIT: diagnose the failure, fix the root cause (not the symptom), then re-run the SAME command via 'cdt-verify -- <cmd>' so the exit code is recorded.$_ESC Do not claim success while this is red."
      printf '{"decision":"block","reason":"%s"}\n' "$_REASON"
      exit 0
    fi
  elif [ "$_VERIF" = "passed" ]; then
    rm -f "$LOOPSTATE" 2>/dev/null
    db_event verify_gate "pass-trusted" "${SESSION_ID:-}" 2>/dev/null
  else
    # ---- No trusted evidence. Degrade to the legacy "a command ran" heuristic when the toolkit is
    # unavailable, so a machine without node still gets the old (weaker) protection rather than none.
    unverified=1
    if [ -z "$_VERIF" ]; then
      VMARK="$(cdt_verify_marker "${SESSION_ID:-default}" 2>/dev/null)"
      [ -n "$VMARK" ] && [ -f "$VMARK" ] && [ ! "$MARK" -nt "$VMARK" ] && unverified=0
      if [ "$unverified" = 1 ] && [ -n "$TRANSCRIPT" ] && cdt_verify_scan_transcript "$TRANSCRIPT" 2>/dev/null; then
        unverified=0
      fi
    fi
    if [ "$unverified" = 0 ]; then
      db_event verify_gate "pass-degraded" "${SESSION_ID:-}" 2>/dev/null
    elif [ ! -f "$VBLOCK" ]; then
      : > "$VBLOCK" 2>/dev/null   # not_run fires once — repeated blocking belongs to a RED verdict, not a missing one
      if [ "$GATE" = "warn" ]; then
        db_event verify_gate "warn" "${SESSION_ID:-}" 2>/dev/null
        echo "claude-dev-team: ⚠ edits were made but no verified test/build/lint/typecheck run followed — verify before trusting this as done (cdt-config verify off to silence)." >&2
      else
        db_event verify_gate "block" "${SESSION_ID:-}" 2>/dev/null
        _R="claude-dev-team: edits were made but no verifying command (test / build / lint / typecheck) ran afterward with a recorded result. Run the project's verifying command as 'cdt-verify -- <cmd>' so its real exit code is captured, then stop. If a subagent already ran it, re-run it through cdt-verify. (Soften: cdt-config verify warn|off.)"
        [ -z "$_TKDIST" ] && _R="$_R NOTE: the toolkit is not built, so only degraded evidence is available."
        printf '{"decision":"block","reason":"%s"}\n' "$_R"
        exit 0
      fi
    fi
  fi
fi

# --- Claim gate: the final message must not assert success the evidence does not support. ------------
# This is the last line of defense and the one that catches the reported failure mode directly: a reply
# saying "done / fixed / all tests pass" while the recorded verdict is red or absent. Fires at most once.
CLAIMGATE="$(grep -E '^CDT_CLAIM_GATE=' "$CDT_HOME/claude-dev-team.env" 2>/dev/null | head -1 | cut -d= -f2-)"
case "$CLAIMGATE" in block|warn|off) : ;; *) CLAIMGATE=block ;; esac
CBLOCK="${TMPDIR:-/tmp}/cdt-claim-blocked-${SESSION_ID:-default}.marker"
if [ "$CLAIMGATE" != "off" ] && [ "$_VERIF" != "passed" ] && [ "$_DOCS_ONLY" != 1 ] && \
   [ ! -f "$CBLOCK" ] && [ -n "$TRANSCRIPT" ] && [ -f "$TRANSCRIPT" ] && command -v python3 >/dev/null 2>&1; then
  # Scan the LAST assistant message only — an earlier "this should fix it" is narration, not a final claim.
  _CLAIM="$(CDT_T="$TRANSCRIPT" python3 - <<'PYC' 2>/dev/null
import json, os, re
last = ""
try:
    with open(os.environ["CDT_T"], encoding="utf-8", errors="replace") as fh:
        for line in fh:
            try: o = json.loads(line)
            except Exception: continue
            if o.get("type") != "assistant": continue
            c = (o.get("message") or {}).get("content")
            if isinstance(c, list):
                t = " ".join(b.get("text", "") for b in c if isinstance(b, dict) and b.get("type") == "text")
            else:
                t = c if isinstance(c, str) else ""
            if t.strip(): last = t
except Exception:
    raise SystemExit
# Success assertions about the WORK. Deliberately narrow: "should fix", "let's verify", questions and
# negations are not claims, and a false positive here blocks an honest session.
PAT = re.compile(r"\b("
    r"all (?:the )?(?:tests?|checks?|gates?|suites?) (?:now )?pass(?:ing|ed)?"
    r"|tests? (?:are |now )?(?:pass(?:ing|ed)|green)"
    r"|(?:everything|it|that|this) (?:is |now )?(?:works?|working|fixed|done|green)"
    r"|(?:the )?(?:bug|issue|problem|failure)s? (?:is|are|has been|have been) (?:now )?(?:fixed|resolved)"
    r"|verified (?:and )?(?:working|passing|green)"
    r"|implementation is complete"
    r")\b", re.I)
NEG = re.compile(r"\b(not|isn'?t|aren'?t|no longer|fail|failing|failed|red|blocked|cannot|can'?t|should|would|once|after|todo)\b", re.I)
for sent in re.split(r"(?<=[.!?\n])\s+", last):
    if PAT.search(sent) and not NEG.search(sent):
        print(sent.strip()[:160]); break
PYC
)"
  if [ -n "$_CLAIM" ]; then
    : > "$CBLOCK" 2>/dev/null
    _EV="${_VERIF:-not_run}"
    [ -n "$_FAILING" ] && _EV="$_EV — red: $(printf '%s' "$_FAILING" | tr '\n' ';')"
    if [ "$CLAIMGATE" = "warn" ]; then
      db_event claim_gate "warn" "${SESSION_ID:-}" 2>/dev/null
      echo "claude-dev-team: ⚠ the reply claims success but recorded verification is $_EV." >&2
    else
      db_event claim_gate "block" "${SESSION_ID:-}" 2>/dev/null
      printf '{"decision":"block","reason":"%s"}\n' "claude-dev-team: your reply claims success — \"$(printf '%s' "$_CLAIM" | sed 's/"/\\"/g')\" — but the recorded verification is $_EV. Either produce the evidence (re-run the verifying command via 'cdt-verify -- <cmd>' and let it pass), or correct the claim: say what is actually red/unverified and report it as PARTIAL or BLOCKER. Do not restate success without evidence. (Soften: cdt-config claim warn|off.)"
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
# TASK_RESULT.json was already written by the finalize run above (the gate needs the verdict first); this
# reuses that payload to surface the staging guard + the cdt-verify nudge. Never blocks.
if [ -n "$_FIN" ]; then
  if command -v python3 >/dev/null 2>&1; then
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
    "claude-dev-team: edits were made — run the completion mandate before finishing (simplify, code-review, reuse-audit, dead-code scan, verify with command output, persist a vault learning). If already done, you may stop."
  exit 0
fi
exit 0
