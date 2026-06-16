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

echo "== 4b. per-agent telemetry: cost-relevant tokens vs cache reads split =="
TR="$SBX/agent-transcript.jsonl"
cat > "$TR" <<'JSONL'
{"type":"assistant","message":{"usage":{"input_tokens":1000,"output_tokens":500,"cache_creation_input_tokens":2000,"cache_read_input_tokens":80000}}}
{"type":"assistant","message":{"usage":{"input_tokens":100,"output_tokens":400,"cache_read_input_tokens":90000}}}
JSONL
# fresh tokens = (1000+500+2000)+(100+400) = 4000 ; cache_read = 80000+90000 = 170000
printf '{"agent_type":"cdt:demo-role","session_id":"s","transcript_path":"%s"}' "$TR" | bash "$REPO/hooks/agent-track.sh"
ROW="$(CDT_DB="$HOME/.claude/claude-dev-team.db" python3 -c 'import os,sqlite3
try:
    c=sqlite3.connect(os.environ["CDT_DB"]); r=c.execute("SELECT tokens,cache_read FROM agent_runs WHERE agent=?",("cdt:demo-role",)).fetchone()
    print("%s|%s"%(r[0],r[1]) if r else "none")
except Exception: print("err")' 2>/dev/null)"
[ "$ROW" = "4000|170000" ] && ok "tokens split fresh=4000 · cache_read=170000 (cache not in the cost figure)" || no "token split wrong (got: $ROW)"
has "$("$BIN/cdt-stats" all 2>&1)" "cache)" "stats shows cache reads separately"

echo "== 4c. verification gate (block a Stop with edits but no verify afterward) =="
lacks() { if printf '%s' "$1" | grep -q -- "$2"; then no "$3"; else ok "$3"; fi; }
vmark() { printf '%s/cdt-verified-%s.marker' "${TMPDIR:-/tmp}" "$1"; }
clrm()  { rm -f "$(vmark "$1")" "${TMPDIR:-/tmp}/cdt-edits-$1.marker" "${TMPDIR:-/tmp}/cdt-verify-blocked-$1.marker" 2>/dev/null; }
EP() { printf '{"session_id":"%s","tool_name":"Edit","tool_input":{"file_path":"%s/none.txt"},"cwd":"%s"}' "$1" "$SBX" "$SBX"; }
BP() { printf '{"session_id":"%s","tool_name":"Bash","tool_input":{"command":"%s"},"tool_response":"%s"}' "$1" "$2" "$3"; }
SP() { printf '{"session_id":"%s","cwd":"%s","transcript_path":"%s"}' "$1" "$SBX" "${2:-}"; }
edit() { EP "$1" | bash "$REPO/hooks/format-on-write.sh" >/dev/null 2>&1; }
runbash() { BP "$1" "$2" "$3" | bash "$REPO/hooks/verify-track.sh" >/dev/null 2>&1; }
stop() { SP "$1" "${2:-}" | bash "$REPO/hooks/completion-guard.sh" 2>&1; }

"$BIN/cdt-config" verify block >/dev/null 2>&1
has "$("$BIN/cdt-config" show 2>&1)" "verify    : block" "config show reports the verify gate"
# (a) edits, no verify -> block
clrm vga; edit vga
has "$(stop vga)" '"decision":"block"' "blocks a Stop with edits but no verify"
# (b) a real verifying command clears it
clrm vgb; edit vgb; runbash vgb "pytest -q" "2 passed in 0.1s"
[ -f "$(vmark vgb)" ] && ok "verify-track marks a real test run" || no "verify-track marks a real test run"
lacks "$(stop vgb)" '"decision":"block"' "passes after a verifying command ran"
# (c) edits AFTER the last verify -> block again
clrm vgc; runbash vgc "npm run test" "ok"; touch -t 202601010000 "$(vmark vgc)" 2>/dev/null; edit vgc
has "$(stop vgc)" '"decision":"block"' "re-blocks when edits come after the last verify"
# (d) once-per-session: a second Stop after a block does not block again
lacks "$(stop vgc)" '"decision":"block"' "fires at most once per session"
# (e) warn never blocks; (f) off disables
clrm vgw; "$BIN/cdt-config" verify warn >/dev/null 2>&1; edit vgw
lacks "$(stop vgw)" '"decision":"block"' "warn mode never blocks"
clrm vgo; "$BIN/cdt-config" verify off >/dev/null 2>&1; edit vgo
lacks "$(stop vgo)" '"decision":"block"' "off mode disables the gate"
"$BIN/cdt-config" verify block >/dev/null 2>&1
# (g) matcher precision: echo is not a verify; a real lint is
clrm vgm; runbash vgm "echo running tests" "running tests"
[ -f "$(vmark vgm)" ] && no "echo is not treated as a verify" || ok "echo is not treated as a verify"
runbash vgm "eslint ." "0 problems"
[ -f "$(vmark vgm)" ] && ok "a real lint is treated as a verify" || no "a real lint is treated as a verify"
# (h) a SUBAGENT that ran the tests clears the gate (the qa-engineer flow)
clrm vgs; edit vgs
SUBTR="$SBX/sub-vgs.jsonl"
printf '%s\n' '{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Bash","input":{"command":"pytest -q"}}]}}' > "$SUBTR"
printf '{"agent_type":"cdt:qa-engineer","session_id":"vgs","transcript_path":"%s"}' "$SUBTR" | bash "$REPO/hooks/agent-track.sh" >/dev/null 2>&1
[ -f "$(vmark vgs)" ] && ok "a subagent test run marks the session verified" || no "a subagent test run marks the session verified"
lacks "$(stop vgs)" '"decision":"block"' "passes when a subagent ran the tests"
# gate outcomes are recorded to the events table
EVN="$(CDT_DB="$HOME/.claude/claude-dev-team.db" python3 -c 'import os,sqlite3
try:
    c=sqlite3.connect(os.environ["CDT_DB"]); print(c.execute("SELECT count(*) FROM events WHERE type=?",("verify_gate",)).fetchone()[0])
except Exception: print(0)' 2>/dev/null)"
[ "${EVN:-0}" -gt 0 ] && ok "verify_gate outcomes recorded to the DB" || no "verify_gate outcomes recorded to the DB"
for s in vga vgb vgc vgw vgo vgm vgs; do clrm $s; done

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

echo "== 8. worktree isolation (cdt-worktree) =="
if command -v git >/dev/null 2>&1; then
  PROJ="$SBX/proj"; mkdir -p "$PROJ"
  ( cd "$PROJ" && git init -q && git config user.email e2e@cdt.local && git config user.name e2e \
      && git commit -q --allow-empty -m init ) >/dev/null 2>&1
  # create -> the checkout + branch exist, and .gitignore gained the worktrees line
  ( cd "$PROJ" && "$BIN/cdt-worktree" new feat ) >/dev/null 2>&1
  [ -d "$PROJ/.claude/worktrees/feat" ] && ok "worktree checkout created" || no "worktree checkout created"
  has "$(cd "$PROJ" && git branch --list worktree-feat 2>&1)" "worktree-feat" "worktree branch created"
  has "$(cat "$PROJ/.gitignore" 2>/dev/null)" ".claude/worktrees/" "worktrees path auto-gitignored"
  has "$(cd "$PROJ" && "$BIN/cdt-worktree" list 2>&1)" "feat" "worktree list shows it"
  has "$(cd "$PROJ" && "$BIN/cdt-worktree" path feat 2>&1)" "worktrees/feat" "worktree path resolves"
  # regression (linked-worktree top resolution): creating from INSIDE a worktree targets the MAIN repo, not nested
  ( cd "$PROJ/.claude/worktrees/feat" && "$BIN/cdt-worktree" new inner ) >/dev/null 2>&1
  { [ -d "$PROJ/.claude/worktrees/inner" ] && [ ! -d "$PROJ/.claude/worktrees/feat/.claude/worktrees/inner" ]; } \
    && ok "create from inside a worktree targets main repo (no nesting)" || no "worktree nesting bug"
  ( cd "$PROJ" && "$BIN/cdt-worktree" rm inner --force ) >/dev/null 2>&1
  # safety: an invalid name (path traversal / injection) is rejected
  if ( cd "$PROJ" && "$BIN/cdt-worktree" new "../evil" ) >/dev/null 2>&1; then no "invalid worktree name rejected"; else ok "invalid worktree name rejected"; fi
  # safety: rm refuses a dirty worktree without --force, then --force removes it
  : > "$PROJ/.claude/worktrees/feat/untracked.txt"
  if ( cd "$PROJ" && "$BIN/cdt-worktree" rm feat ) >/dev/null 2>&1; then no "dirty worktree rm refused without --force"; else ok "dirty worktree rm refused without --force"; fi
  ( cd "$PROJ" && "$BIN/cdt-worktree" rm feat --force ) >/dev/null 2>&1
  [ -d "$PROJ/.claude/worktrees/feat" ] && no "worktree --force removal" || ok "worktree --force removal"
  # branch-reuse: re-creating 'feat' reuses the leftover worktree-feat branch (and clean prunes cleanly)
  ( cd "$PROJ" && "$BIN/cdt-worktree" new feat ) >/dev/null 2>&1
  [ -d "$PROJ/.claude/worktrees/feat" ] && ok "worktree re-created (branch reused)" || no "worktree re-created (branch reused)"
  has "$(cd "$PROJ" && "$BIN/cdt-worktree" clean 2>&1)" "pruned" "worktree clean prunes"
else
  ok "git not present — worktree test skipped (cdt-worktree needs git)"
fi

echo "== 9. autonomous orchestration (cdt-auto router + cost governor) =="
NOW="$(date +%s 2>/dev/null || echo 0)"
fresh() { printf '%s' "{\"weekly\":$1,\"session\":10,\"ts\":$NOW}" > "$HOME/.claude/.cdt-usage.json"; }
"$BIN/cdt-config" autonomy assist >/dev/null 2>&1
has "$("$BIN/cdt-auto" status 2>&1)" "assist" "autonomy status reflects mode"
# gate team: DENY off → ALLOW on+headroom → ASK over ceiling
"$BIN/cdt-config" teams off >/dev/null 2>&1
has "$("$BIN/cdt-auto" gate team 2>&1)" "DENY" "gate team DENY when engine off"
"$BIN/cdt-config" teams on >/dev/null 2>&1
fresh 20; has "$("$BIN/cdt-auto" gate team 2>&1)" "ALLOW" "gate team ALLOW within budget"
fresh 90; has "$("$BIN/cdt-auto" gate team 2>&1)" "ASK" "gate team ASK over weekly ceiling"
# gate scale: DENY off → assist ASK → auto ALLOW/ASK(ceiling)/ASK(unknown, fail-safe)
"$BIN/cdt-config" scale off >/dev/null 2>&1
has "$("$BIN/cdt-auto" gate scale 2>&1)" "DENY" "gate scale DENY when engine off"
"$BIN/cdt-config" scale on >/dev/null 2>&1
fresh 20; has "$("$BIN/cdt-auto" gate scale 2>&1)" "ASK" "gate scale ASK in assist mode"
"$BIN/cdt-config" autonomy auto >/dev/null 2>&1
fresh 20; has "$("$BIN/cdt-auto" gate scale 2>&1)" "ALLOW" "gate scale ALLOW in auto mode within budget"
fresh 90; has "$("$BIN/cdt-auto" gate scale 2>&1)" "ASK" "gate scale ASK in auto mode over ceiling"
rm -f "$HOME/.claude/.cdt-usage.json"
has "$("$BIN/cdt-auto" gate scale 2>&1)" "ASK" "gate scale ASK when budget unknown (fail-safe, not ALLOW)"
# teams flag landed in settings.json env
has "$(cat "$HOME/.claude/settings.json" 2>/dev/null)" "CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS" "agent-team flag written to settings.json"
# explain classifier — wide → BREADTH, stuck → DEPTH, small → BOUNDED
has "$("$BIN/cdt-auto" explain "audit every endpoint across the repo" 2>&1)" "BREADTH" "explain routes a wide audit to BREADTH"
has "$("$BIN/cdt-auto" explain "the test is flaky and I cannot figure out the root cause" 2>&1)" "DEPTH" "explain routes a stuck bug to DEPTH"
has "$("$BIN/cdt-auto" explain "fix a typo in the readme" 2>&1)" "BOUNDED" "explain routes a small task to BOUNDED"
# off disables all escalation
"$BIN/cdt-config" autonomy off >/dev/null 2>&1
has "$("$BIN/cdt-auto" gate team 2>&1)" "DENY" "gate DENY when autonomy off"

echo
if [ "$fail" = 0 ]; then echo "E2E PASSED"; else echo "E2E FAILED"; fi
exit "$fail"
