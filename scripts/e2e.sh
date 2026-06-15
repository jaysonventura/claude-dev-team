#!/usr/bin/env bash
# scripts/e2e.sh — end-to-end integration test for claude-dev-team.
# Runs entirely in a SANDBOX (a throwaway temp HOME), so it never touches your real ~/.claude.
# Exercises the whole chain — bootstrap -> doctor -> deps -> learn->recall -> task->stats ->
# statusline->budget(eco) -> config on/off -> notify->log — and exits non-zero on any failure.
#   Run locally:  bash scripts/e2e.sh      (also runs in CI)
set -u

REPO="$(cd "$(dirname "$0")/.." && pwd)"
SBX="$(mktemp -d 2>/dev/null)" || { echo "e2e: cannot create sandbox"; exit 1; }
trap 'rm -rf "$SBX"' EXIT
export HOME="$SBX"
mkdir -p "$HOME/.claude"
touch "$HOME/.claude/.cdt-menubar-disabled"   # never build the macOS menu bar inside the test
BIN="$HOME/.claude/bin"

fail=0
ok() { echo "  ok:   $1"; }
no() { echo "  FAIL: $1"; fail=1; }
has() {  # has <output> <needle> <label>
  if printf '%s' "$1" | grep -q -- "$2"; then ok "$3"
  else no "$3"; printf '        wanted "%s" — got: %s\n' "$2" "$(printf '%s' "$1" | head -1)"; fi
}

echo "== 1. bootstrap (SessionStart hook installs CLIs + vault + DB) =="
bash "$REPO/hooks/session-start-vault.sh" >/dev/null 2>&1
{ [ -x "$BIN/cdt-doctor" ] && [ -x "$BIN/cdt-recall" ] && [ -x "$BIN/cdt-config" ]; } && ok "CLIs installed to sandbox bin" || no "CLIs installed"
[ -d "$HOME/.claude/vault" ] && ok "vault bootstrapped" || no "vault bootstrapped"

echo "== 2. doctor + deps run =="
has "$("$BIN/cdt-doctor" 2>&1)" "fail" "doctor prints a tally"
has "$("$BIN/cdt-deps" 2>&1)" "python3" "deps lists prerequisites"

echo "== 3. learn -> recall =="
"$BIN/cdt-learn" "sandbox marker quuxzzy lesson" testing >/dev/null 2>&1
has "$("$BIN/cdt-recall" "quuxzzy" 2>&1)" "quuxzzy" "recall surfaces a learned lesson"

echo "== 4. task -> stats =="
"$BIN/cdt-task" T2 shipped 1 "e2e sandbox task" >/dev/null 2>&1
has "$("$BIN/cdt-stats" all 2>&1)" "T2" "stats reflects the logged task"

echo "== 5. statusline -> budget (eco conserves when weekly is high) =="
SL_JSON='{"model":{"display_name":"Opus"},"effort":{"level":"xhigh"},"rate_limits":{"seven_day":{"used_percentage":90},"five_hour":{"used_percentage":10}}}'
has "$(printf '%s' "$SL_JSON" | "$BIN/cdt-statusline" 2>&1)" "wk" "statusline renders usage"
has "$(CDT_ECO_THRESHOLD=80 "$BIN/cdt-budget" 2>&1)" "CONSERVE" "budget recommends CONSERVE at high weekly usage"

echo "== 6. config off/on flips the orchestration injection =="
"$BIN/cdt-config" off >/dev/null 2>&1
has "$(bash "$REPO/hooks/session-start-vault.sh" 2>/dev/null)" "DISABLED" "config off -> hook says DISABLED"
"$BIN/cdt-config" on >/dev/null 2>&1
has "$(bash "$REPO/hooks/session-start-vault.sh" 2>/dev/null)" "orchestrator" "config on -> orchestration injected"

echo "== 7. notify -> vault status-log =="
"$BIN/cdt-notify" INFO "e2e-sandbox-line" >/dev/null 2>&1
has "$(cat "$HOME/.claude/vault/status-log.md" 2>/dev/null)" "e2e-sandbox-line" "notify writes the vault log"

echo
if [ "$fail" = 0 ]; then echo "E2E PASSED"; else echo "E2E FAILED"; fi
exit "$fail"
