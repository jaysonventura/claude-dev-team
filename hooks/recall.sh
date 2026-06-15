#!/usr/bin/env bash
# cdt-recall "<task or query>" [N] — retrieve the most RELEVANT durable lessons from the vault for a
# given task, so the orchestrator pulls only what matters instead of re-reading the whole learnings
# file. Cost-effective memory: targeted recall scales as the vault grows (no 4 KB dump, no truncation).
#
# Pure stdlib (python3) lexical ranking — no embedding model, no network, no third-party deps.
# Fail-open: prints nothing and exits 0 if the vault or python3 is unavailable.
set +e

QUERY="$1"; N="${2:-5}"
case "$N" in ''|*[!0-9]*) N=5 ;; esac
[ -z "$QUERY" ] && { echo "usage: cdt-recall \"<task or query>\" [N]"; exit 0; }

VAULT="${CDT_VAULT:-$HOME/.claude/vault}"
LEARN="$VAULT/learnings.md"
[ -f "$LEARN" ] || exit 0

if command -v python3 >/dev/null 2>&1; then
  QUERY="$QUERY" N="$N" LEARN="$LEARN" python3 - <<'PY'
import os, re
query = os.environ.get("QUERY", "")
try:
    n = max(1, int(os.environ.get("N", "5") or 5))
except ValueError:
    n = 5
path = os.environ.get("LEARN", "")

STOP = set("the a an and or of to in is for on with by it this that be are as at from "
           "your you our we i if then so not no run use used using when where what how".split())

def toks(s):
    return [t for t in re.split(r"[^a-z0-9]+", s.lower()) if len(t) > 2 and t not in STOP]

qt = toks(query)
if not qt:
    raise SystemExit(0)            # no usable query terms — nothing to rank on

scored = []
try:
    for raw in open(path, encoding="utf-8", errors="ignore"):
        s = raw.strip()
        if not s.startswith("- ["):  # only real learning bullets: "- [YYYY-MM-DD] ..."
            continue
        lt = toks(s)
        if not lt:
            continue
        low = s.lower()
        score = sum(lt.count(t) for t in qt)          # term overlap
        for i in range(len(qt) - 1):                   # phrase bonus for adjacent query terms
            if f"{qt[i]} {qt[i+1]}" in low:
                score += 2
        if score > 0:
            scored.append((score, s))
except OSError:
    raise SystemExit(0)

scored.sort(key=lambda x: -x[0])
top = scored[:n]
if top:
    print("Relevant past lessons (cdt-recall):")
    for _, s in top:
        print(" ", s)
PY
else
  # Degraded fallback (no python3): grep the longest query word.
  word="$(printf '%s' "$QUERY" | tr 'A-Z' 'a-z' | grep -oE '[a-z0-9]{4,}' | awk '{ print length, $0 }' | sort -rn | head -1 | cut -d" " -f2-)"
  [ -n "$word" ] && grep -i -- "$word" "$LEARN" 2>/dev/null | grep '^- \[' | head -n "$N"
fi
exit 0
