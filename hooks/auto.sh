#!/usr/bin/env bash
# cdt-auto — the Autonomous Agent Orchestration control plane + cost governor.
#
# CDT triages every task (T0–T3) and, on top of that, an autonomous MODE ROUTER decides whether to stay
# BOUNDED (default, cheap) or escalate to DEPTH (an agent-team Bug Council that debates) or BREADTH (a
# dynamic workflow that fans out) — but only when the work-shape signature demands it, and only within a
# budget. This CLI is that controller's surface:
#
#   cdt-auto status                 show autonomy mode, engines, caps, and live budget headroom
#   cdt-auto gate <team|scale>      the GOVERNOR — orchestrator MUST consult before any escalation
#                                   -> prints ALLOW (proceed) | ASK (confirm with the human) | DENY (stay bounded)
#   cdt-auto explain "<task>"       advisory preview of which mode the live router would lean to
#   cdt-auto off|assist|auto        set the autonomy leash (delegates to cdt-config autonomy)
#
# Read-mostly + fail-SAFE: the governor keeps "autonomous" and "cost-effective on Max 5x" both true.
# Expensive modes are gated by the autonomy leash + each engine's on/off + a weekly-budget ceiling, and
# when the budget can't be read (telemetry off / stale) the gate ASKs rather than ALLOWing a blind spend.
set -u

CDT_HOME="$HOME/.claude"
ENV_FILE="${CDT_ENV_FILE:-$CDT_HOME/claude-dev-team.env}"
CACHE="$CDT_HOME/.cdt-usage.json"
SLICE="$CDT_HOME/.cdt/scale-slice.json"
DB="${CDT_DB:-$CDT_HOME/claude-dev-team.db}"
BIN="$CDT_HOME/bin"

get_env() { grep -E "^$1=" "$ENV_FILE" 2>/dev/null | head -1 | cut -d= -f2-; }

AUTONOMY="$(get_env CDT_AUTONOMY)"; [ -z "$AUTONOMY" ] && AUTONOMY="auto"
TEAMS="$(get_env CDT_TEAMS)";       [ -z "$TEAMS" ] && TEAMS="on"
SCALE="$(get_env CDT_SCALE)";       [ -z "$SCALE" ] && SCALE="on"
CEILING="$(get_env CDT_AUTONOMY_WEEKLY_CEILING)"; case "$CEILING" in ''|*[!0-9]*) CEILING=85 ;; esac
TEAM_MAX="$(get_env CDT_TEAM_MAX)";  case "$TEAM_MAX" in ''|*[!0-9]*) TEAM_MAX=5 ;; esac
SCALE_CAP="$(get_env CDT_SCALE_TOKEN_CAP)"; case "$SCALE_CAP" in ''|*[!0-9]*) SCALE_CAP=2000000 ;; esac

# Latest cached weekly usage % (written by the status line / menu bar). Empty if unknown OR stale
# (no/old timestamp) — so the governor fails SAFE (asks) rather than gating today's spend on a week-old
# reading. Stale window mirrors cdt-budget (1800s).
weekly_pct() {
  command -v python3 >/dev/null 2>&1 || { echo ""; return; }
  [ -f "$CACHE" ] || { echo ""; return; }
  CACHE="$CACHE" python3 -c 'import os,json,time
try:
    d=json.load(open(os.environ["CACHE"]))
    ts=int(d.get("ts",0) or 0)
    print("" if (not ts or time.time()-ts > 1800) else int(d.get("weekly",0)))
except Exception:
    print("")' 2>/dev/null
}

# Cumulative delegated (subagent) token spend so far — a proxy for "how much has this run cost".
agent_token_total() {
  { [ -f "$DB" ] && command -v python3 >/dev/null 2>&1; } || { echo 0; return; }
  CDT_DB="$DB" python3 -c 'import os,sqlite3
try: print(sqlite3.connect(os.environ["CDT_DB"]).execute("SELECT COALESCE(SUM(tokens),0) FROM agent_runs").fetchone()[0])
except Exception: print(0)' 2>/dev/null
}

# 0 (true) iff a slice baseline exists and is recent (< 1h) — used to require slice-first before a fan-out.
slice_fresh() {
  [ -f "$SLICE" ] && command -v python3 >/dev/null 2>&1 || return 1
  SLICE="$SLICE" python3 -c 'import os,json,time
try:
    d=json.load(open(os.environ["SLICE"])); raise SystemExit(0 if time.time()-int(d.get("ts",0) or 0) < 3600 else 1)
except SystemExit: raise
except Exception: raise SystemExit(1)' 2>/dev/null
}

# Slice-first: measure a small slice, then PROJECT the full fan-out cost before committing to it.
cmd_slice() {
  case "${1:-}" in
    record)
      local n="${2:-0}"; case "$n" in ''|*[!0-9]*) n=0 ;; esac
      command -v python3 >/dev/null 2>&1 || { echo "cdt-auto: python3 required for slice baselines"; return; }
      mkdir -p "$CDT_HOME/.cdt" 2>/dev/null
      local tot; tot="$(agent_token_total)"
      SLICE="$SLICE" N="$n" TOT="$tot" python3 -c 'import os,json,time
json.dump({"ts":int(time.time()),"items":int(os.environ["N"]),"tokens0":int(os.environ["TOT"])}, open(os.environ["SLICE"],"w"))' 2>/dev/null \
        && echo "cdt-auto: slice baseline recorded ($n items; delegated-token mark $tot). Run the slice, then: cdt-auto project <total_items>"
      ;;
    *) echo "usage: cdt-auto slice record <n_items_in_the_slice>" ;;
  esac
}

cmd_project() {
  local total="${1:-0}"; case "$total" in ''|*[!0-9]*) total=0 ;; esac
  [ -f "$SLICE" ] && command -v python3 >/dev/null 2>&1 || { echo "STOP  no slice baseline — measure a small slice first: cdt-auto slice record <n>"; return; }
  local tot; tot="$(agent_token_total)"
  SLICE="$SLICE" TOTAL="$total" NOWTOK="$tot" CAP="$SCALE_CAP" python3 -c 'import os,json
try: d=json.load(open(os.environ["SLICE"]))
except Exception: print("STOP  slice baseline unreadable — re-record: cdt-auto slice record <n>"); raise SystemExit(0)
items=int(d.get("items",0) or 0); t0=int(d.get("tokens0",0) or 0)
spent=max(0,int(os.environ["NOWTOK"])-t0); total=int(os.environ["TOTAL"]); cap=int(os.environ["CAP"])
if items<=0 or spent<=0:
    print("ASK   slice produced no measurable delegated spend yet — run the slice (or estimate manually) before fanning out"); raise SystemExit(0)
per=spent/items; proj=int(per*total)
verdict="ALLOW" if proj<=cap else "STOP"
print("%s projected ~%d tokens for %d items (%.0f/item from a %d-item slice); cap %d" % (verdict,proj,total,per,items,cap))' 2>/dev/null
}

cmd_status() {
  local wk; wk="$(weekly_pct)"
  echo "CDT autonomous orchestration:"
  echo "  autonomy : $AUTONOMY   (off = bounded only · assist = auto-teams, ask-before-workflows · auto = self-run both within budget)"
  echo "  teams    : $TEAMS   (DEPTH — agent-team Bug Council; needs CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1)"
  echo "  scale    : $SCALE   (BREADTH — dynamic-workflow fan-out; needs Claude Code >= 2.1.154)"
  echo "  caps     : teammates <= $TEAM_MAX · weekly ceiling ${CEILING}% · scale token cap $SCALE_CAP"
  if [ -n "$wk" ]; then
    echo "  budget   : weekly ${wk}%   (escalation pauses to ASK at/above ${CEILING}%)"
  else
    echo "  budget   : weekly ?%   (telemetry off — enable: cdt-config statusline on. Until then the"
    echo "             ceiling can't be checked, so 'auto' mode ASKs before any self-run escalation.)"
  fi
  echo
  echo "  Default path is BOUNDED (cheap). It escalates only on signature — stuck bug -> team; large"
  echo "  homogeneous set -> workflow — and only within budget. Tune: cdt-config autonomy|teams|scale."
}

# The governor. Encodes the assist-vs-auto policy + each engine's on/off + the weekly ceiling.
# First token is ALLOW | ASK | DENY so the orchestrator can branch on it.
cmd_gate() {
  local kind="${1:-}" wk
  if [ "$AUTONOMY" = "off" ]; then echo "DENY  autonomy is off — stay bounded (enable: cdt-config autonomy assist)"; return; fi
  wk="$(weekly_pct)"
  case "$kind" in
    team)
      if [ "$TEAMS" != "on" ]; then echo "DENY  agent-teams disabled (cdt-config teams on — also sets the experimental flag)"; return; fi
      if [ -n "$wk" ] && [ "$wk" -ge "$CEILING" ]; then echo "ASK   weekly ${wk}% >= ceiling ${CEILING}% — confirm the team spend before convening"; return; fi
      # auto mode self-runs without asking; if it can't see the budget, fail SAFE and ask rather than run blind
      if [ "$AUTONOMY" = "auto" ] && [ -z "$wk" ]; then echo "ASK   weekly budget unknown (enable status line / menu bar) — confirm the team spend"; return; fi
      echo "ALLOW agent-team within budget (<= ${TEAM_MAX} teammates, time-boxed 1-2 rounds, then dissolve)"
      ;;
    scale)
      if [ "$SCALE" != "on" ]; then echo "DENY  scale mode disabled (cdt-config scale on — needs Claude Code >= 2.1.154)"; return; fi
      if [ "$AUTONOMY" = "assist" ]; then echo "ASK   assist mode proposes workflows — confirm before summoning (slice-first, cap ${SCALE_CAP} tokens)"; return; fi
      # auto mode: never self-run a fan-out without budget headroom — unknown budget fails SAFE to ASK
      if [ -z "$wk" ]; then echo "ASK   weekly budget unknown (enable status line / menu bar) — confirm the workflow spend"; return; fi
      if [ "$wk" -ge "$CEILING" ]; then echo "ASK   weekly ${wk}% >= ceiling ${CEILING}% — confirm the workflow spend"; return; fi
      # Slice-first is now a code gate: don't fan out until a small slice has been measured + projected.
      if ! slice_fresh; then echo "ASK   slice-first required — measure a small slice, then project, before fanning out: cdt-auto slice record <n> ; cdt-auto project <total_items>"; return; fi
      echo "ALLOW workflow within budget (slice measured; cap ${SCALE_CAP} tokens, log what's dropped)"
      ;;
    *) echo "usage: cdt-auto gate <team|scale>" ;;
  esac
}

# Budget-elastic fan-out: how many parallel agents to dispatch for a wave at this tier, sized to remaining
# weekly headroom. Full tier width when there's room; trim toward the floor near/over the ceiling;
# conservative when budget is unknown. NEVER below the floor (security-review + qa verify always survive).
cmd_fanout() {
  local tier wk maxn floor name mid
  tier="$(printf '%s' "${1:-}" | tr 'a-z' 'A-Z')"
  case "$tier" in
    T0) echo "0  T0 solo — do it yourself, no fan-out"; return ;;
    T1) echo "1  T1 pair — 1 specialist; minimal path, no budget trimming"; return ;;
    T2) maxn=5; floor=3; name="squad" ;;
    T3) maxn=10; floor=6; name="full" ;;
    *)  echo "usage: cdt-auto fanout <T0|T1|T2|T3>"; return ;;
  esac
  wk="$(weekly_pct)"
  if [ -z "$wk" ]; then
    echo "$floor  ${tier} ${name}: ~${floor} agents (conservative) — budget unknown; enable status line / menu bar for full elastic width"
  elif [ "$wk" -ge "$CEILING" ]; then
    echo "$floor  ${tier} ${name}: trim to ~${floor} essential agents — weekly ${wk}% >= ceiling ${CEILING}%; keep security-review + qa verify"
  elif [ "$wk" -ge "$((CEILING-15))" ]; then
    mid=$(( (floor + maxn + 1) / 2 ))
    echo "$mid  ${tier} ${name}: ~${mid} agents (mid width) — weekly ${wk}% nearing ceiling ${CEILING}%; keep security-review + qa verify"
  else
    echo "$maxn  ${tier} ${name}: up to ${maxn} parallel agents (full width) — weekly ${wk}%, comfortable headroom"
  fi
}

# Advisory preview only — the live router decides with full task context. Heuristic keyword classifier.
cmd_explain() {
  local task="$*"
  if [ -z "$task" ]; then echo "usage: cdt-auto explain \"<task>\""; return; fi
  TASK="$task" TEAMS="$TEAMS" SCALE="$SCALE" AUTONOMY="$AUTONOMY" python3 - <<'PY' 2>/dev/null || echo "cdt-auto: python3 unavailable for explain"
import os
t = os.environ["TASK"].lower()
breadth = any(w in t for w in ["every ","all ","across the","repo-wide","repowide","audit","migrat",
    "each file","exhaustive","entire codebase","all endpoints","all routes","all files","sweep","whole repo"])
depth = any(w in t for w in ["stuck","can't figure","cannot figure","intermittent","flaky","race condition",
    "deadlock","heisenbug","root cause","why does","why is","keeps failing","no idea","can not figure"])
print("cdt-auto: advisory preview (the live router decides with full context)\n")
if breadth:
    nxt = "propose a dynamic workflow and ASK first" if os.environ["AUTONOMY"] == "assist" else "summon a workflow within budget"
    print("  lean: BREADTH — a large homogeneous set (audit / migration / exhaustive review).")
    print("        -> would %s, slice-first, capped." % nxt)
elif depth:
    print("  lean: DEPTH — a hard/ambiguous diagnosis. If it gets stuck, an agent-team Bug Council")
    print("        convenes (<= 5 lenses, debate, time-boxed).")
else:
    print("  lean: BOUNDED — normal tiered dispatch (T0-T3). No escalation; the cheapest path.")
print("\n  Requires the engine enabled (teams=%s, scale=%s) + budget headroom." % (os.environ["TEAMS"], os.environ["SCALE"]))
PY
}

case "${1:-status}" in
  status|show|"")  cmd_status ;;
  gate)            shift; cmd_gate "$@" ;;
  fanout)          shift; cmd_fanout "$@" ;;
  explain)         shift; cmd_explain "$@" ;;
  slice)           shift; cmd_slice "$@" ;;
  project)         shift; cmd_project "$@" ;;
  off|assist|auto) "$BIN/cdt-config" autonomy "$1" 2>/dev/null || echo "set it via: cdt-config autonomy $1" ;;
  on)              "$BIN/cdt-config" autonomy assist 2>/dev/null || echo "set it via: cdt-config autonomy assist" ;;
  help|-h|--help)  echo "usage: cdt-auto {status | gate <team|scale> | fanout <tier> | explain \"<task>\" | slice record <n> | project <total> | off | assist | auto}" ;;
  *)               echo "usage: cdt-auto {status | gate <team|scale> | fanout <tier> | explain \"<task>\" | slice record <n> | project <total> | off | assist | auto}" ;;
esac
exit 0
