#!/usr/bin/env bash
# cdt-contract — manage the per-agent exclusive-file contracts used by scope/sprawl detection.
# The PreToolUse(Task) hook captures these automatically from the dispatch directive; this CLI is the
# explicit/manual fallback and the way to inspect findings. Session key: CDT_SESSION_ID (else "default").
#
#   cdt-contract add <agent> <exclusive-csv> [read-csv]   record a contract for the current session
#   cdt-contract list | show | findings | reset
set +e

CDT_HOME="$HOME/.claude"
SID="${CDT_SESSION_ID:-default}"
DIR="$CDT_HOME/.cdt/contracts/$SID"

case "${1:-list}" in
  add)
    agent="$2"; excl="$3"; read="${4:-}"
    [ -n "$agent" ] && [ -n "$excl" ] || { echo "usage: cdt-contract add <agent> <exclusive-csv> [read-csv]"; exit 0; }
    command -v python3 >/dev/null 2>&1 || { echo "cdt-contract: python3 required"; exit 0; }
    CDT_DIR="$CDT_HOME/.cdt/contracts" CSID="$SID" AGENT="$agent" EXCL="$excl" READ="$read" CWD="$PWD" python3 - <<'PY'
import os, json, re, time
base = os.path.join(os.environ["CDT_DIR"], os.environ["CSID"], "pending")
os.makedirs(base, exist_ok=True)
seq = "%d-%d" % (int(time.time() * 1e9), os.getpid())
agent = os.environ["AGENT"]; san = re.sub(r"[/:]+", "-", agent)
excl = [x.strip() for x in os.environ["EXCL"].split(",") if x.strip()]
read = [x.strip() for x in os.environ["READ"].split(",") if x.strip()]
json.dump({"seq": seq, "session_id": os.environ["CSID"], "agent_type": agent, "exclusive": excl,
           "read": read, "cwd": os.environ["CWD"], "created": seq},
          open(os.path.join(base, "%s__%s.json" % (seq, san)), "w"))
print("cdt-contract: recorded %s -> exclusive=%s" % (agent, excl))
PY
    ;;
  list)
    [ -d "$DIR" ] || { echo "(no contracts for session $SID)"; exit 0; }
    for sub in pending claimed; do
      for f in "$DIR/$sub"/*.json; do
        [ -e "$f" ] || continue
        printf '%-8s %s\n' "$sub" "$(basename "$f")"
      done
    done ;;
  show)
    found=0
    for f in "$DIR"/pending/*.json "$DIR"/claimed/*.json; do
      [ -e "$f" ] || continue
      found=1; echo "--- $(basename "$f")"; cat "$f"; echo
    done
    [ "$found" = 0 ] && echo "(no contracts for session $SID)" ;;
  findings)
    if [ -s "$DIR/findings.jsonl" ]; then cat "$DIR/findings.jsonl"; else echo "(no scope findings for session $SID)"; fi ;;
  reset)
    rm -rf "$DIR" 2>/dev/null; echo "cdt-contract: cleared contracts for session $SID" ;;
  *)
    echo "usage: cdt-contract {add <agent> <exclusive-csv> [read-csv]|list|show|findings|reset}" ;;
esac
exit 0
