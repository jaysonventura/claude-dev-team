#!/usr/bin/env bash
# PreToolUse (Bash) hook: route verifying commands through `cdt-verify` so their REAL exit code is recorded.
#
# Why this exists. The Stop gate can only be as good as its evidence, and the PostToolUse payload does not
# carry a reliable exit code (tool_response shape is undocumented) — so a bare `npm test` produces an event
# with exitCode:null, which can never prove anything. `cdt-verify -- <cmd>` is a transparent wrapper: same
# stdout/stderr, same exit code, plus one trusted line in .claude/runtime/verify-events.jsonl. Asking for it
# here is what makes "verification: passed" mean the tests actually passed.
#
# Fail-open everywhere. It denies ONLY when cdt-verify is genuinely runnable — a missing or broken toolkit
# must never make the project's test command un-runnable.
#   cdt-config verify-wrap block|warn|off   (default block)
set +e

INPUT="$(cat 2>/dev/null)"
CDT_HOME="$HOME/.claude"

_EN="$(grep -E '^CDT_ENABLED=' "$CDT_HOME/claude-dev-team.env" 2>/dev/null | head -1 | cut -d= -f2-)"
[ "$_EN" = "0" ] && exit 0

MODE="$(grep -E '^CDT_VERIFY_WRAP=' "$CDT_HOME/claude-dev-team.env" 2>/dev/null | head -1 | cut -d= -f2-)"
case "$MODE" in block|warn|off) : ;; *) MODE=block ;; esac
[ "$MODE" = "off" ] && exit 0

# The wrapper must exist AND execute. A dangling symlink into a pruned plugin version passes `-L` and fails
# at exec, so probe it for real — denying in favour of a binary that cannot run would break every test run.
VERIFY_BIN=""
for _c in "$CDT_HOME/bin/cdt-verify" "$(command -v cdt-verify 2>/dev/null)"; do
  [ -n "$_c" ] && [ -x "$_c" ] && [ -e "$_c" ] && { VERIFY_BIN="$_c"; break; }
done
[ -n "$VERIFY_BIN" ] || exit 0

HOOKS_DIR="$(cd "$(dirname "$0")" 2>/dev/null && pwd)"
# shellcheck source=/dev/null
. "$HOOKS_DIR/verify-lib.sh" 2>/dev/null || exit 0

CMD="$(CDT_PAYLOAD="$INPUT" python3 -c 'import os,json,sys
try: o=json.loads(os.environ["CDT_PAYLOAD"])
except Exception: sys.exit(0)
ti=o.get("tool_input") or {}
sys.stdout.write(ti.get("command","") if isinstance(ti,dict) else "")' 2>/dev/null)"
[ -n "$CMD" ] || exit 0

# Already recording? Leave it alone — and never recurse into the wrapper's own child process.
case "$CMD" in *cdt-verify*) exit 0 ;; esac
[ "${CDT_IN_VERIFY:-0}" = "1" ] && exit 0

cdt_verify_match "$CMD" || exit 0

# A pipeline or chain (`npm test | tail`, `a && b`) has no single meaningful exit code to record, and
# rewriting it would change its semantics. Nudge, never block.
case "$CMD" in
  *"|"*|*"&&"*|*";"*)   # `|` already covers `||`
    [ "$MODE" = "block" ] && echo "claude-dev-team: verify command is part of a chain — run the verifying part alone as 'cdt-verify -- <cmd>' to record trusted evidence." >&2
    exit 0 ;;
esac

if [ "$MODE" = "warn" ]; then
  echo "claude-dev-team: ⚠ run this as 'cdt-verify -- $CMD' so its exit code is recorded as trusted evidence." >&2
  exit 0
fi

# permissionDecision:deny returns the reason to the model as feedback; it re-issues the wrapped command.
CDT_CMD="$CMD" python3 -c 'import os,json
c=os.environ["CDT_CMD"]
print(json.dumps({"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny",
  "permissionDecisionReason":"claude-dev-team: run verifying commands through cdt-verify so the real exit code is recorded as evidence — otherwise the Stop gate cannot tell a passing run from a failing one. Re-run it as:  cdt-verify -- %s   (same output, same exit code, one trusted event). Soften with: cdt-config verify-wrap warn|off." % c}},
  separators=(",", ":")))' 2>/dev/null
exit 0
