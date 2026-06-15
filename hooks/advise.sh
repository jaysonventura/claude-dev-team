#!/usr/bin/env bash
# cdt-advise "<task>" — an ADVISORY tier/effort prior learned from past task outcomes in the state DB.
# The orchestrator still decides; this is transparent, overridable guidance (never a hidden policy).
# Pure stdlib (python3's built-in sqlite3 — no external binary, no deps). Fail-open: silent on any issue.
set +e

QUERY="$1"
[ -z "$QUERY" ] && { echo "usage: cdt-advise \"<task>\""; exit 0; }

DB="${CDT_DB:-$HOME/.claude/claude-dev-team.db}"
[ -f "$DB" ] || exit 0
command -v python3 >/dev/null 2>&1 || exit 0

QUERY="$QUERY" DB="$DB" python3 - <<'PY'
import os, re, sqlite3
from collections import Counter

query = os.environ.get("QUERY", "")
db = os.environ.get("DB", "")
STOP = set("the a an and or of to in is for on with by it this that be are as at from your you our we "
           "add fix make build update create new a an to with".split())

def toks(s):
    return [t for t in re.split(r"[^a-z0-9]+", s.lower()) if len(t) > 2 and t not in STOP]

qt = set(toks(query))
if not qt:
    raise SystemExit(0)

try:
    con = sqlite3.connect(db)
    con.row_factory = sqlite3.Row
    rows = con.execute(
        "SELECT description, tier, status, iterations FROM tasks WHERE description IS NOT NULL").fetchall()
except Exception:
    raise SystemExit(0)

scored = []
for r in rows:
    overlap = len(qt & set(toks(r["description"] or "")))
    if overlap > 0:
        scored.append((overlap, r))
if not scored:
    raise SystemExit(0)

scored.sort(key=lambda x: -x[0])
sample = [r for _, r in scored[:8]]

tiers = Counter((r["tier"] or "?") for r in sample)
iters = [r["iterations"] for r in sample if isinstance(r["iterations"], int)]
blockers = sum(1 for r in sample if (r["status"] or "").lower() in ("blocker", "deferred"))
avg = round(sum(iters) / len(iters), 1) if iters else None
top_tier = tiers.most_common(1)[0][0]

print(f"Routing prior (cdt-advise — from {len(sample)} similar past task(s)):")
print("  tier mix: " + " ".join(f"{t}×{c}" for t, c in tiers.most_common()))
if avg is not None:
    print(f"  iterations: avg {avg}, max {max(iters)}")
if blockers:
    print(f"  warning: {blockers}/{len(sample)} similar task(s) hit a blocker/deferred")
budget = f"; budget ~{int(round(avg)) + 1} iteration(s)" if avg is not None else ""
print(f"  suggestion: lean {top_tier}{budget}. (advisory — you decide.)")
PY
exit 0
