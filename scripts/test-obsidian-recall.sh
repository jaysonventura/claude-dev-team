#!/usr/bin/env bash
# scripts/test-obsidian-recall.sh — unit tests for hooks/obsidian_recall.py (pure-stdlib BM25 ranker).
# Deterministic, dependency-free. Builds a fixture vault, runs the ranker, asserts ranking + behavior.
set -u
cd "$(dirname "$0")/.." || exit 1
RANKER="hooks/obsidian_recall.py"
fail=0
err() { echo "  FAIL: $*"; fail=1; }

echo "== obsidian_recall.py (BM25 ranker) =="

command -v python3 >/dev/null 2>&1 || { echo "  SKIP: python3 not found"; exit 0; }

# Fixture vault: three clearly-distinct notes.
VAULT="$(mktemp -d)"
mkdir -p "$VAULT/notes"
cat > "$VAULT/notes/auth.md"  <<'MD'
# Authentication Notes
Debugging the OAuth login token refresh bug. The authentication token expired and
the session failed to refresh, logging the user out.
MD
cat > "$VAULT/pasta.md" <<'MD'
# Pasta Recipe
Boil water, add tomato and basil. A simple weeknight dinner with garlic and olive oil.
MD
cat > "$VAULT/cache.md" <<'MD'
# Caching Layer
Redis caching for performance. Tune the eviction policy and measure latency under load.
MD

# 1. Ranking: the auth note must be the top result for an auth query.
out="$(python3 "$RANKER" "$VAULT" "authentication token refresh bug" 5 2>/dev/null)"
first="$(printf '%s\n' "$out" | grep -m1 '^- ')"
printf '%s' "$first" | grep -q 'auth.md' || err "auth.md should rank first; got: ${first:-<none>}"

# 2. Relevance ordering: auth.md appears before pasta.md in the ranked output.
auth_ln="$(printf '%s\n' "$out" | grep -n 'auth.md'  | head -1 | cut -d: -f1)"
pasta_ln="$(printf '%s\n' "$out" | grep -n 'pasta.md' | head -1 | cut -d: -f1)"
if [ -n "$auth_ln" ] && [ -n "$pasta_ln" ]; then
  [ "$auth_ln" -lt "$pasta_ln" ] || err "auth.md should outrank pasta.md"
fi

# 3. Top-N limit: N=1 yields exactly one result item.
n1="$(python3 "$RANKER" "$VAULT" "authentication token" 1 2>/dev/null | grep -c '^- ')"
[ "$n1" = "1" ] || err "N=1 should return exactly 1 item; got $n1"

# 4. A snippet from the matched note is included (contains a query term).
printf '%s' "$out" | grep -qi 'token' || err "output should include a snippet containing a query term"

# 5. Empty / no-usable-query → no output, exit 0 (fail-open, never noise).
empty="$(python3 "$RANKER" "$VAULT" "the a an" 5 2>/dev/null)"
[ -z "$empty" ] || err "stopword-only query should produce no output"

# 6. Missing root → no output, exit 0 (fail-open).
python3 "$RANKER" "$VAULT/does-not-exist" "token" 5 >/dev/null 2>&1 || err "missing root must still exit 0"

echo "== cdt-obsidian recall (subcommand gating) =="

# 7. Disabled → recall is silent (off always wins).
cli_off="$(CDT_OBSIDIAN=off CDT_OBSIDIAN_RECALL_ROOT="$VAULT" bash hooks/obsidian.sh recall "authentication token" 5 2>/dev/null)"
[ -z "$cli_off" ] || err "recall must be silent when obsidian is disabled; got: $cli_off"

# 8. Enabled (path set, auto-use) → prints the section + surfaces the relevant note.
cli_on="$(CDT_OBSIDIAN_VAULT="$VAULT/CDT" CDT_OBSIDIAN_RECALL_ROOT="$VAULT" bash hooks/obsidian.sh recall "authentication token refresh bug" 5 2>/dev/null)"
printf '%s' "$cli_on" | grep -q '## Relevant Obsidian notes' || err "recall (enabled) should print the section header"
printf '%s' "$cli_on" | grep -q 'auth.md' || err "recall (enabled) should surface auth.md"

rm -rf "$VAULT" 2>/dev/null
if [ "$fail" = 0 ]; then echo "  ALL OBSIDIAN-RECALL TESTS PASS"; else echo "  OBSIDIAN-RECALL TESTS FAILED"; fi
exit "$fail"
