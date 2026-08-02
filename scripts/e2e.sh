#!/usr/bin/env bash
# scripts/e2e.sh — end-to-end integration test for claude-dev-team.
# Runs entirely in a SANDBOX (a throwaway temp HOME), so it never touches your real ~/.claude.
# Exercises the whole chain — bootstrap -> doctor -> deps -> learn->recall -> task->stats ->
# statusline->budget(eco) -> config on/off — and exits non-zero on any failure.
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
clrm()  { rm -f "$(vmark "$1")" "${TMPDIR:-/tmp}/cdt-edits-$1.marker" "${TMPDIR:-/tmp}/cdt-verify-blocked-$1.marker" "${TMPDIR:-/tmp}/cdt-scope-blocked-$1.marker" "${TMPDIR:-/tmp}/cdt-memory-blocked-$1.marker" 2>/dev/null; }
EP() { printf '{"session_id":"%s","tool_name":"Edit","tool_input":{"file_path":"%s/none.txt"},"cwd":"%s"}' "$1" "$SBX" "$SBX"; }
BP() { printf '{"session_id":"%s","tool_name":"Bash","tool_input":{"command":"%s"},"tool_response":"%s"}' "$1" "$2" "$3"; }
SP() { printf '{"session_id":"%s","cwd":"%s","transcript_path":"%s"}' "$1" "$SBX" "${2:-}"; }
edit() { EP "$1" | bash "$REPO/hooks/format-on-write.sh" >/dev/null 2>&1; }
runbash() { BP "$1" "$2" "$3" | bash "$REPO/hooks/verify-track.sh" >/dev/null 2>&1; }
stop() { SP "$1" "${2:-}" | bash "$REPO/hooks/completion-guard.sh" 2>&1; }

"$BIN/cdt-config" verify block >/dev/null 2>&1
has "$("$BIN/cdt-config" show 2>&1)" "verify    : block" "config show reports the verify gate"
# Trusted evidence: only `cdt-verify` writes a real exit code, into .claude/runtime/verify-events.jsonl.
# Seeded directly here so the gate can be driven through PASS / FAIL / stale without running real suites.
VEVENTS="$SBX/.claude/runtime/verify-events.jsonl"
vclear() { rm -f "$VEVENTS" 2>/dev/null; }
vevent() {  # vevent <command> <exitCode> [iso_ts]
  mkdir -p "$(dirname "$VEVENTS")" 2>/dev/null
  CDT_C="$1" CDT_E="$2" CDT_TS="${3:-}" CDT_W="$SBX" python3 -c 'import os,json,datetime
print(json.dumps({"ts": os.environ["CDT_TS"] or datetime.datetime.utcnow().strftime("%Y-%m-%dT%H:%M:%SZ"),
 "command": os.environ["CDT_C"], "type": "test", "exitCode": int(os.environ["CDT_E"]),
 "cwd": os.environ["CDT_W"], "source": "cdt-verify"}))' >> "$VEVENTS" 2>/dev/null
}
lclr() { rm -f "${TMPDIR:-/tmp}/cdt-loop-$1.state" "${TMPDIR:-/tmp}/cdt-loop-exhausted-$1.marker" "${TMPDIR:-/tmp}/cdt-claim-blocked-$1.marker" 2>/dev/null; }

# (a) edits, no verify evidence -> block
clrm vga; lclr vga; vclear; edit vga
has "$(stop vga)" '"decision":"block"' "blocks a Stop with edits but no verify"
# (b) a TRUSTED green event clears it
clrm vgb; lclr vgb; vclear; edit vgb; vevent "pytest -q" 0
lacks "$(stop vgb)" '"decision":"block"' "passes on a trusted PASSING verify event"
# (c) a merely-typed test command is NOT evidence — the whole point of the tightening: the old gate
#     accepted it, so a RED suite could end the session as "done".
clrm vgc; lclr vgc; vclear; edit vgc; runbash vgc "pytest -q" "2 passed in 0.1s"
has "$(stop vgc)" '"decision":"block"' "a typed test command alone is NOT accepted as verification"
# (d) a trusted FAILING event blocks, names the red command, and keeps blocking (the Task Loop)
clrm vgf; lclr vgf; vclear; edit vgf; vevent "npm test" 1
OUT1="$(stop vgf)"
has "$OUT1" '"decision":"block"' "blocks on a trusted FAILING verify event"
has "$OUT1" 'npm test' "the block names the failing command"
has "$OUT1" 'iteration 1/5' "the block reports the Task Loop iteration"
OUT2="$(stop vgf)"
has "$OUT2" 'iteration 2/5' "a red verdict blocks AGAIN (loop), not once-per-session"
has "$OUT2" 'bug-council' "an unchanged failure signature escalates to the Bug Council"
# (e) fixing it turns the verdict green and releases the loop
vevent "npm test" 0
lacks "$(stop vgf)" '"decision":"block"' "a passing re-run releases the loop"
# (f) the loop is capped — it must never trap a session forever
clrm vgx; lclr vgx; vclear; edit vgx; vevent "npm test" 1
i=0; while [ "$i" -lt 5 ]; do stop vgx >/dev/null 2>&1; i=$((i+1)); done
lacks "$(stop vgx)" '"decision":"block"' "stops blocking after CDT_MAX_ITERATIONS"
has "$(stop vgx 2>&1)" "BLOCKER" "reports the capped session as BLOCKER, not done"
# (g) stale evidence: a green run from BEFORE the edit proves nothing about the code that replaced it
clrm vgt; lclr vgt; vclear; vevent "npm test" 0 "2020-01-01T00:00:00Z"; edit vgt
has "$(stop vgt)" '"decision":"block"' "a green run older than the last edit does not count"
# (h) warn never blocks; off disables
clrm vgw; lclr vgw; vclear; "$BIN/cdt-config" verify warn >/dev/null 2>&1; edit vgw; vevent "npm test" 1
lacks "$(stop vgw)" '"decision":"block"' "warn mode never blocks"
clrm vgo; lclr vgo; vclear; "$BIN/cdt-config" verify off >/dev/null 2>&1; edit vgo; vevent "npm test" 1
lacks "$(stop vgo)" '"decision":"block"' "off mode disables the gate"
"$BIN/cdt-config" verify block >/dev/null 2>&1
# (i) matcher precision (still used by the degraded path + verify-wrap): echo is not a verify, lint is
clrm vgm; runbash vgm "echo running tests" "running tests"
[ -f "$(vmark vgm)" ] && no "echo is not treated as a verify" || ok "echo is not treated as a verify"
runbash vgm "eslint ." "0 problems"
[ -f "$(vmark vgm)" ] && ok "a real lint is treated as a verify" || no "a real lint is treated as a verify"
# (j) degraded mode: with the toolkit disabled the OLD marker heuristic still protects the session
clrm vgd; lclr vgd; vclear; "$BIN/cdt-config" toolkit off >/dev/null 2>&1
edit vgd; has "$(stop vgd)" '"decision":"block"' "degraded (no toolkit): still blocks edits with no verify"
clrm vgd; lclr vgd; edit vgd; runbash vgd "pytest -q" "2 passed"
lacks "$(stop vgd)" '"decision":"block"' "degraded (no toolkit): falls back to the marker heuristic"
"$BIN/cdt-config" toolkit on >/dev/null 2>&1
for s in vgb vgc vgf vgx vgt vgw vgo vgd; do clrm $s; lclr $s; done; vclear

echo "== 4c-2. claim gate (a reply may not assert success the evidence does not support) =="
# The verify gate blocks FIRST on a red verdict, so asserting only "something blocked" would pass without
# the claim gate existing at all. These drive the states where the verify gate deliberately does NOT
# block — warn mode and an exhausted loop — which is exactly where a false "done" would otherwise escape.
claimtr() { printf '%s\n' "{\"type\":\"assistant\",\"message\":{\"content\":[{\"type\":\"text\",\"text\":\"$1\"}]}}" > "$SBX/claim.jsonl"; echo "$SBX/claim.jsonl"; }
"$BIN/cdt-config" verify warn >/dev/null 2>&1
clrm cg1; lclr cg1; vclear; edit cg1; vevent "npm test" 1
CT="$(claimtr 'Done — all tests pass and the bug is fixed.')"
OUTC1="$(stop cg1 "$CT")"
has "$OUTC1" 'claims success' "verify=warn: a false success claim is still blocked"
has "$OUTC1" 'recorded verification is failed' "the block states what the evidence actually says"
has "$OUTC1" 'npm test' "the block names the red command"
# Honest reporting must pass — a gate that blocks truthful text is worse than no gate.
clrm cg3; lclr cg3; vclear; edit cg3; vevent "npm test" 1
CT3="$(claimtr 'Two tests are still failing; reporting this as BLOCKER, not done.')"
lacks "$(stop cg3 "$CT3")" 'claims success' "an honest failure report is not treated as a claim"
# Hedges and future tense are not assertions of completed success.
clrm cg5; lclr cg5; vclear; edit cg5; vevent "npm test" 1
CT5="$(claimtr 'This should fix it once the suite passes.')"
lacks "$(stop cg5 "$CT5")" 'claims success' "a hedge (should/once) is not a success claim"
clrm cg4; lclr cg4; vclear; edit cg4; vevent "npm test" 0
CT4="$(claimtr 'Done — all tests pass.')"
lacks "$(stop cg4 "$CT4")" '"decision":"block"' "the same claim passes when the verdict is GREEN"
"$BIN/cdt-config" verify block >/dev/null 2>&1
# The critical path: the loop hit its cap and stopped blocking. The session must not end on "done".
clrm cg7; lclr cg7; vclear; edit cg7; vevent "npm test" 1
i=0; while [ "$i" -lt 6 ]; do stop cg7 >/dev/null 2>&1; i=$((i+1)); done
CT7="$(claimtr 'Done — everything works now.')"
has "$(stop cg7 "$CT7")" 'claims success' "after the loop cap, a success claim is still blocked"
"$BIN/cdt-config" claim off >/dev/null 2>&1
clrm cg6; lclr cg6; vclear; "$BIN/cdt-config" verify warn >/dev/null 2>&1; edit cg6; vevent "npm test" 1
CT6="$(claimtr 'Done — all tests pass.')"
lacks "$(stop cg6 "$CT6")" 'claims success' "claim gate honors off"
"$BIN/cdt-config" claim block >/dev/null 2>&1; "$BIN/cdt-config" verify block >/dev/null 2>&1
for s in cg1 cg3 cg4 cg5 cg6 cg7; do clrm $s; lclr $s; done; vclear

echo "== 4c-3. verify-wrap (exit codes get recorded, and it never bricks a test command) =="
wrap() { printf '{"session_id":"w1","tool_name":"Bash","tool_input":{"command":"%s"}}' "$1" | bash "$REPO/hooks/verify-wrap.sh" 2>&1; }
# With no runnable cdt-verify it MUST stay silent: denying in favour of a binary that cannot run would
# make the project's own test command un-runnable.
rm -f "$BIN/cdt-verify" 2>/dev/null
lacks "$(wrap 'npm test')" 'deny' "no runnable cdt-verify -> never denies (fail-open)"
ln -sf "$REPO/toolkit/dist/cli/cdt-verify.js" "$BIN/cdt-verify" 2>/dev/null
has "$(wrap 'npm test')" '"permissionDecision":"deny"' "denies a bare verify command"
has "$(wrap 'npm test')" 'cdt-verify -- npm test' "tells the model the exact wrapped command"
lacks "$(wrap 'cdt-verify -- npm test')" 'deny' "never denies an already-wrapped command (no recursion)"
lacks "$(wrap 'echo hello')" 'deny' "leaves non-verify commands alone"
lacks "$(wrap 'npm test | tail -5')" 'deny' "a pipeline has no single exit code -> nudge, never deny"
"$BIN/cdt-config" verify-wrap off >/dev/null 2>&1
lacks "$(wrap 'npm test')" 'deny' "verify-wrap honors off"
"$BIN/cdt-config" verify-wrap block >/dev/null 2>&1
# gate outcomes are recorded to the events table
EVN="$(CDT_DB="$HOME/.claude/claude-dev-team.db" python3 -c 'import os,sqlite3
try:
    c=sqlite3.connect(os.environ["CDT_DB"]); print(c.execute("SELECT count(*) FROM events WHERE type=?",("verify_gate",)).fetchone()[0])
except Exception: print(0)' 2>/dev/null)"
[ "${EVN:-0}" -gt 0 ] && ok "verify_gate outcomes recorded to the DB" || no "verify_gate outcomes recorded to the DB"
for s in vga vgb vgc vgw vgo vgm vgs; do clrm $s; done

echo "== 4d. grounding: builder agents carry the context7 doc tools =="
for a in backend-engineer frontend-engineer mobile-engineer data-engineer devops-engineer qa-engineer; do
  if grep -q 'mcp__plugin_context7_context7__resolve-library-id' "$REPO/agents/$a.md" \
     && grep -q 'mcp__plugin_context7_context7__query-docs' "$REPO/agents/$a.md"; then
    ok "$a carries context7 (resolve-library-id + query-docs)"
  else
    no "$a missing context7 tools (grounding)"
  fi
done

echo "== 4e. scope/sprawl detection (contracts -> overreach/collision) =="
CROOT="$SBX/repo"; mkdir -p "$CROOT"
SCD() { printf '%s/.claude/.cdt/contracts/%s' "$HOME" "$1"; }
TP() { printf '{"session_id":"%s","tool_name":"Task","tool_input":{"subagent_type":"%s","description":"d","prompt":"do it. CDT-CONTRACT: exclusive=%s ; read=types/**"},"cwd":"%s"}' "$1" "$2" "$3" "$CROOT"; }
mksub() { printf '{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Write","input":{"file_path":"%s"}}]}}\n' "$1" > "$2"; }
astop() { printf '{"agent_type":"%s","session_id":"%s","transcript_path":"%s","cwd":"%s"}' "$1" "$2" "$3" "$CROOT" | bash "$REPO/hooks/agent-track.sh" >/dev/null 2>&1; }
njson() { local d="$1" n=0 f; for f in "$d"/*.json; do [ -e "$f" ] && n=$((n+1)); done; echo "$n"; }
hasjson() { local f; for f in "$1"/*.json; do [ -e "$f" ] && return 0; done; return 1; }

# (a) PreToolUse(Task) captures a pending contract from the dispatch directive
S=sc1; rm -rf "$(SCD $S)"
TP $S "cdt:backend-engineer" "api/**" | bash "$REPO/hooks/contract-capture.sh" >/dev/null 2>&1
hasjson "$(SCD $S)/pending" && ok "PreToolUse(Task) captured a pending contract" || no "contract capture"
# (b) in-scope write -> claimed (atomic mv), no finding
mksub "$CROOT/api/users.ts" "$SBX/tr-sc1.jsonl"; astop "cdt:backend-engineer" $S "$SBX/tr-sc1.jsonl"
hasjson "$(SCD $S)/claimed" && ok "SubagentStop claimed the contract (atomic mv)" || no "contract claim"
[ -s "$(SCD $S)/findings.jsonl" ] && no "in-scope write left no findings" || ok "in-scope write left no findings"
# (c) out-of-scope write -> overreach
S=sc2; rm -rf "$(SCD $S)"
TP $S "cdt:backend-engineer" "api/**" | bash "$REPO/hooks/contract-capture.sh" >/dev/null 2>&1
mksub "$CROOT/frontend/app.tsx" "$SBX/tr-sc2.jsonl"; astop "cdt:backend-engineer" $S "$SBX/tr-sc2.jsonl"
has "$(cat "$(SCD $S)/findings.jsonl" 2>/dev/null)" "overreach" "out-of-scope write flagged as overreach"
# (d) collision: backend writes into frontend's scope
S=sc3; rm -rf "$(SCD $S)"
TP $S "cdt:backend-engineer" "api/**" | bash "$REPO/hooks/contract-capture.sh" >/dev/null 2>&1
TP $S "cdt:frontend-engineer" "ui/**" | bash "$REPO/hooks/contract-capture.sh" >/dev/null 2>&1
mksub "$CROOT/ui/button.tsx" "$SBX/tr-sc3.jsonl"; astop "cdt:backend-engineer" $S "$SBX/tr-sc3.jsonl"
has "$(cat "$(SCD $S)/findings.jsonl" 2>/dev/null)" "collision" "writing into a peer's scope flagged as collision"
# (e) Stop gate: block vs warn (isolate from the verify gate)
"$BIN/cdt-config" verify off >/dev/null 2>&1; "$BIN/cdt-config" scope block >/dev/null 2>&1
edit sc2
rm -f "${TMPDIR:-/tmp}/cdt-scope-blocked-sc2.marker"   # fresh once-per-session marker (across reruns too)
has "$(stop sc2)" '"decision":"block"' "scope=block stops a session with findings"
rm -f "${TMPDIR:-/tmp}/cdt-scope-blocked-sc2.marker"
"$BIN/cdt-config" scope warn >/dev/null 2>&1
lacks "$(stop sc2)" '"decision":"block"' "scope=warn never blocks"
"$BIN/cdt-config" verify block >/dev/null 2>&1
# (f) concurrency: two same-type contracts, two SubagentStops -> each claimed exactly once
S=sc4; rm -rf "$(SCD $S)"
TP $S "cdt:backend-engineer" "api/**" | bash "$REPO/hooks/contract-capture.sh" >/dev/null 2>&1
TP $S "cdt:backend-engineer" "api/**" | bash "$REPO/hooks/contract-capture.sh" >/dev/null 2>&1
[ "$(njson "$(SCD $S)/pending")" = "2" ] && ok "two contracts captured for the same agent type" || no "two-contract capture"
mksub "$CROOT/api/a.ts" "$SBX/tr-4a.jsonl"; mksub "$CROOT/api/b.ts" "$SBX/tr-4b.jsonl"
astop "cdt:backend-engineer" $S "$SBX/tr-4a.jsonl"; astop "cdt:backend-engineer" $S "$SBX/tr-4b.jsonl"
{ [ "$(njson "$(SCD $S)/claimed")" = "2" ] && [ "$(njson "$(SCD $S)/pending")" = "0" ]; } \
  && ok "each contract claimed exactly once (no double-claim)" || no "claim accounting under concurrency"
# (g) scope events recorded
SCEV="$(CDT_DB="$HOME/.claude/claude-dev-team.db" python3 -c 'import os,sqlite3
try: print(sqlite3.connect(os.environ["CDT_DB"]).execute("SELECT count(*) FROM events WHERE type LIKE ?",("scope%",)).fetchone()[0])
except Exception: print(0)' 2>/dev/null)"
[ "${SCEV:-0}" -gt 0 ] && ok "scope events recorded to the DB" || no "scope events recorded to the DB"
for s in sc1 sc2 sc3 sc4; do rm -rf "$(SCD $s)"; clrm $s; done

echo "== 4f. memory gate + recall ranking =="
LEARN="$HOME/.claude/vault/learnings.md"
"$BIN/cdt-config" verify off >/dev/null 2>&1; "$BIN/cdt-config" memory block >/dev/null 2>&1
# (a) team-tier session (>=1 agent_run) + edits + no fresh lesson -> block
clrm mg1
printf '{"agent_type":"cdt:demo","session_id":"mg1","transcript_path":""}' | bash "$REPO/hooks/agent-track.sh" >/dev/null 2>&1
touch -t 202001010000 "$LEARN" 2>/dev/null
edit mg1
has "$(stop mg1)" '"decision":"block"' "memory gate blocks a team-tier session with no persisted lesson"
# (b) after a lesson is persisted -> pass
rm -f "${TMPDIR:-/tmp}/cdt-memory-blocked-mg1.marker"
"$BIN/cdt-learn" "mg1 captured a durable lesson" testing >/dev/null 2>&1
lacks "$(stop mg1)" '"decision":"block"' "memory gate passes after a lesson is persisted"
# (c) solo session (no agent_runs) is exempt
clrm mg2; touch -t 202001010000 "$LEARN" 2>/dev/null; edit mg2
lacks "$(stop mg2)" '"decision":"block"' "memory gate never fires for a solo (non-team) session"
"$BIN/cdt-config" memory warn >/dev/null 2>&1; "$BIN/cdt-config" verify block >/dev/null 2>&1
# (d) recall recency: the newer of two equally-relevant lessons ranks first
printf -- '- [2020-01-01] epsilonquux ranking probe older entry\n- [2026-06-16] epsilonquux ranking probe newer entry\n' >> "$LEARN"
RANK="$(CDT_VAULT="$HOME/.claude/vault" CDT_DB="$HOME/.claude/claude-dev-team.db" "$BIN/cdt-recall" "epsilonquux ranking probe" 5)"
NP="$(printf '%s\n' "$RANK" | grep -n 'newer entry' | head -1 | cut -d: -f1)"
OP="$(printf '%s\n' "$RANK" | grep -n 'older entry' | head -1 | cut -d: -f1)"
{ [ -n "$NP" ] && [ -n "$OP" ] && [ "$NP" -lt "$OP" ]; } && ok "recall ranks the newer lesson first (recency)" || no "recall recency ordering (new=$NP old=$OP)"
# (e) memory events recorded
MEV="$(CDT_DB="$HOME/.claude/claude-dev-team.db" python3 -c 'import os,sqlite3
try: print(sqlite3.connect(os.environ["CDT_DB"]).execute("SELECT count(*) FROM events WHERE type=?",("memory_gate",)).fetchone()[0])
except Exception: print(0)' 2>/dev/null)"
[ "${MEV:-0}" -gt 0 ] && ok "memory_gate events recorded to the DB" || no "memory_gate events recorded"
clrm mg1; clrm mg2

echo "== 4g. shared-context packs (dedup) =="
CXR="$SBX/cxrepo"; mkdir -p "$CXR"
printf 'export function alpha(a){}\nexport class Beta {}\nconst x = 1\n' > "$CXR/a.ts"
printf 'def gamma():\n    pass\nclass Delta:\n    pass\n' > "$CXR/b.py"
CDT_SESSION_ID=cx1 "$BIN/cdt-context" pack "$CXR/a.ts" "$CXR/b.py" >/dev/null 2>&1
PK="$(CDT_SESSION_ID=cx1 "$BIN/cdt-context" show 2>&1)"
has "$PK" "a.ts" "context pack lists the files"
has "$PK" "alpha" "context pack extracts a TS signature (alpha)"
has "$PK" "gamma" "context pack extracts a Python signature (gamma)"
lacks "$PK" "const x" "context pack omits non-signature lines"
CDT_SESSION_ID=cx1 "$BIN/cdt-context" reset >/dev/null 2>&1

echo "== 4h. production-grade model right-sizing (cdt-route) =="
has "$("$BIN/cdt-route" "add auth token refresh" 2>&1)" "opus" "route: risk-flagged work -> Opus"
has "$("$BIN/cdt-route" "scaffold a CRUD endpoint" 2>&1)" "sonnet" "route: substantive throughput -> Sonnet"
has "$("$BIN/cdt-route" "rename a variable across files" 2>&1)" "haiku" "route: trivial mechanical -> fast-ops/Haiku"
has "$("$BIN/cdt-route" "design the caching architecture" 2>&1)" "opus" "route: design/architecture -> Opus"

echo "== 4i. quality-via-parallelism (bounded patterns documented) =="
SK="$(cat "$REPO/skills/orchestration/SKILL.md")"
has "$SK" "Adversarial verify" "SKILL documents adversarial verify"
has "$SK" "Diverse-lens review" "SKILL documents diverse-lens review"
has "$SK" "Design judge-panel" "SKILL documents the design judge-panel"
[ -f "$REPO/commands/adversarial.md" ] && ok "/cdt:adversarial command present" || no "/cdt:adversarial command present"
has "$(sed -n '/STEP 3f/,/STEP 4/p' "$REPO/skills/orchestration/SKILL.md")" "never Haiku" "STEP 3f stays above the production-grade floor (no Haiku)"

echo "== 4j. adaptive advise (agent mix from telemetry) =="
has "$("$BIN/cdt-advise" "sandbox task" 2>&1)" "agent mix" "advise recommends an agent mix from telemetry"
has "$("$BIN/cdt-advise" "sandbox task" 2>&1)" "cdt-route" "advise points at cdt-route for model sizing"

echo "== 4k. automation-first (prefer repo automation over manual commands) =="
[ -f "$REPO/skills/automation-first/SKILL.md" ] && ok "automation-first skill present" || no "automation-first skill present"
AF="$(cat "$REPO/skills/automation-first/SKILL.md" 2>/dev/null)"
has "$AF" "make up-dev" "automation-first documents make up-dev for dev"
has "$AF" "STOP and report" "automation-first: stop + report on Makefile failure"
for a in backend frontend mobile devops qa data; do
  has "$(cat "$REPO/agents/$a-engineer.md")" "automation-first" "$a-engineer carries the automation-first rule"
done
has "$(cat "$REPO/agents/code-reviewer.md")" "Automation usage" "code-reviewer flags manual-command usage"
has "$(cat "$REPO/skills/orchestration/SKILL.md")" "automation-first" "orchestration skill routes to automation-first"

echo "== 5. statusline -> budget (eco conserves when weekly is high) =="
SL_JSON='{"model":{"display_name":"Opus"},"effort":{"level":"xhigh"},"rate_limits":{"seven_day":{"used_percentage":90},"five_hour":{"used_percentage":10}}}'
has "$(printf '%s' "$SL_JSON" | "$BIN/cdt-statusline" 2>&1)" "weekly" "statusline renders usage"
has "$(CDT_ECO_THRESHOLD=80 "$BIN/cdt-budget" 2>&1)" "CONSERVE" "budget recommends CONSERVE at high weekly usage"

echo "== 6. config off/on flips the orchestration injection =="
"$BIN/cdt-config" off >/dev/null 2>&1
has "$(bash "$REPO/hooks/session-start-vault.sh" 2>/dev/null)" "DISABLED" "config off -> hook says DISABLED"
"$BIN/cdt-config" on >/dev/null 2>&1
has "$(bash "$REPO/hooks/session-start-vault.sh" 2>/dev/null)" "orchestrator" "config on -> orchestration injected"

echo "== 7. worktree isolation (cdt-worktree) =="
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

echo "== 8. autonomous orchestration (cdt-auto router + cost governor) =="
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
fresh 20; has "$("$BIN/cdt-auto" gate scale 2>&1)" "ASK" "gate scale ASK without a slice baseline (slice-first required)"
"$BIN/cdt-auto" slice record 5 >/dev/null 2>&1
fresh 20; has "$("$BIN/cdt-auto" gate scale 2>&1)" "ALLOW" "gate scale ALLOW in auto mode after slice-first"
rm -f "$HOME/.claude/.cdt/scale-slice.json"
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
# elastic fan-out (P1): full width with headroom, trim toward floor near ceiling, conservative if unknown
fresh 20; has "$("$BIN/cdt-auto" fanout T3 2>&1)" "full width" "fanout T3 -> full width at low weekly usage"
fresh 20; has "$("$BIN/cdt-auto" fanout T3 2>&1)" "10" "fanout T3 -> up to 10 agents with headroom"
fresh 90; has "$("$BIN/cdt-auto" fanout T3 2>&1)" "trim" "fanout T3 -> trims near the weekly ceiling"
fresh 90; has "$("$BIN/cdt-auto" fanout T3 2>&1)" "security" "fanout keeps the security + qa floor when trimming"
rm -f "$HOME/.claude/.cdt-usage.json"
has "$("$BIN/cdt-auto" fanout T2 2>&1)" "conservative" "fanout -> conservative when budget unknown"
has "$("$BIN/cdt-auto" fanout T0 2>&1)" "solo" "fanout T0 -> solo (no fan-out)"

echo "== 8b. slice-first projection + orchestrator overhead (cost truthfulness) =="
# measure a slice, add some delegated spend, then project the full fan-out vs the cap
"$BIN/cdt-auto" slice record 2 >/dev/null 2>&1
printf '{"agent_type":"cdt:slicer","session_id":"slc","transcript_path":"%s"}' "$TR" | bash "$REPO/hooks/agent-track.sh" >/dev/null 2>&1
has "$("$BIN/cdt-auto" project 10 2>&1)" "ALLOW" "project: a small slice extrapolates under the cap -> ALLOW"
has "$("$BIN/cdt-auto" project 100000000 2>&1)" "STOP" "project: a huge fan-out over the cap -> STOP"
rm -f "$HOME/.claude/.cdt/scale-slice.json"
# orchestrator overhead recorded at Stop (main-session tokens vs delegated)
"$BIN/cdt-config" verify off >/dev/null 2>&1
clrm oh1; edit oh1
printf '{"session_id":"oh1","cwd":"%s","transcript_path":"%s"}' "$SBX" "$TR" | bash "$REPO/hooks/completion-guard.sh" >/dev/null 2>&1
"$BIN/cdt-config" verify block >/dev/null 2>&1
OHEV="$(CDT_DB="$HOME/.claude/claude-dev-team.db" python3 -c 'import os,sqlite3
try: print(sqlite3.connect(os.environ["CDT_DB"]).execute("SELECT count(*) FROM events WHERE type=?",("orch_overhead",)).fetchone()[0])
except Exception: print(0)' 2>/dev/null)"
[ "${OHEV:-0}" -gt 0 ] && ok "orchestration overhead recorded at Stop (main vs delegated tokens)" || no "orch_overhead recorded"
has "$("$BIN/cdt-stats" all 2>&1)" "Orchestration overhead" "stats shows the orchestration overhead line"
clrm oh1

echo
if [ "$fail" = 0 ]; then echo "E2E PASSED"; else echo "E2E FAILED"; fi
exit "$fail"
