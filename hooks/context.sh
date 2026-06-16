#!/usr/bin/env bash
# cdt-context — build a SHARED CONTEXT PACK once (file list + key signatures) so parallel agents consume
# a distilled manifest instead of each re-reading the whole codebase. Saves tokens AND ramp time, and the
# stable manifest is a prompt-cache-friendly prefix across the wave. Session key: CDT_SESSION_ID.
#
#   cdt-context pack <path>...   distill the given files into the session's pack
#   cdt-context show | path | reset
set +e

CDT_HOME="$HOME/.claude"
SID="${CDT_SESSION_ID:-default}"
DIR="$CDT_HOME/.cdt/context"
PACK="$DIR/$SID.md"

# Language-agnostic "signature-ish" lines (exports / functions / classes / types / routes) — a cheap
# structural summary, not a parse. Single-quoted so the regex metachars are literal.
SIG_RE='^[[:space:]]*(export |async function |function |class |def |interface |type |enum |struct |trait |impl |func |public |private |protected |module\.exports|const [A-Za-z0-9_]+[[:space:]]*=[[:space:]]*(async[[:space:]]*)?\(|@app\.|@router\.)'

case "${1:-show}" in
  pack)
    shift
    [ "$#" -gt 0 ] || { echo "usage: cdt-context pack <path>..."; exit 0; }
    mkdir -p "$DIR" 2>/dev/null
    {
      echo "# CDT context pack — session $SID"
      echo "# Distilled shared context: READ this manifest instead of re-discovering the codebase."
      echo
      echo "## Files ($#)"
      for f in "$@"; do echo "- $f"; done
      echo
      echo "## Signatures"
      for f in "$@"; do
        [ -f "$f" ] || continue
        echo "### $f"
        grep -nE "$SIG_RE" "$f" 2>/dev/null | head -20 | cut -c1-140 | sed 's/^/    /'
        echo
      done
    } > "$PACK" 2>/dev/null
    echo "cdt-context: wrote pack for session $SID ($# file(s)) -> $PACK"
    ;;
  show)  if [ -f "$PACK" ]; then cat "$PACK"; else echo "(no context pack for session $SID)"; fi ;;
  path)  echo "$PACK" ;;
  reset) rm -f "$PACK" 2>/dev/null; echo "cdt-context: cleared pack for session $SID" ;;
  *)     echo "usage: cdt-context {pack <path>...|show|path|reset}" ;;
esac
exit 0
