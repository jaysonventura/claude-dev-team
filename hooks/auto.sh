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
# Read-mostly + fail-open. The gate keeps "autonomous" and "cost-effective on Max 5x" both true:
# expensive modes are gated by the autonomy leash + each engine's on/off + a weekly-budget ceiling.
set -u

CDT_HOME="$HOME/.claude"
ENV_FILE="${CDT_ENV_FILE:-$CDT_HOME/claude-dev-team.env}"
CACHE="$CDT_HOME/.cdt-usage.json"
BIN="$CDT_HOME/bin"

get_env() { grep -E "^$1=" "$ENV_FILE" 2>/dev/null | head -1 | cut -d= -f2-; }

AUTONOMY="$(get_env CDT_AUTONOMY)"; [ -z "$AUTONOMY" ] && AUTONOMY="assist"
TEAMS="$(get_env CDT_TEAMS)";       [ -z "$TEAMS" ] && TEAMS="off"
SCALE="$(get_env CDT_SCALE)";       [ -z "$SCALE" ] && SCALE="off"
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
      echo "ALLOW workflow within budget (slice-first, cap ${SCALE_CAP} tokens, log what's dropped)"
      ;;
    *) echo "usage: cdt-auto gate <team|scale>" ;;
  esac
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
  explain)         shift; cmd_explain "$@" ;;
  off|assist|auto) "$BIN/cdt-config" autonomy "$1" 2>/dev/null || echo "set it via: cdt-config autonomy $1" ;;
  on)              "$BIN/cdt-config" autonomy assist 2>/dev/null || echo "set it via: cdt-config autonomy assist" ;;
  help|-h|--help)  echo "usage: cdt-auto {status | gate <team|scale> | explain \"<task>\" | off | assist | auto}" ;;
  *)               echo "usage: cdt-auto {status | gate <team|scale> | explain \"<task>\" | off | assist | auto}" ;;
esac
exit 0
