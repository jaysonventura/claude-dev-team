#!/usr/bin/env bash
# cdt-recall "<task or query>" [N] — retrieve the most RELEVANT durable lessons from the vault for a
# given task, so the orchestrator pulls only what matters instead of re-reading the whole learnings
# file. Cost-effective memory: targeted recall scales as the vault grows (no 4 KB dump, no truncation).
#
# Ranking (pure stdlib python3 — no embedding model, no network): lexical term/phrase overlap, then
# re-ranked among the relevant lessons by RECENCY (newer wins) and OUTCOME (lessons whose terms appear in
# painful past tasks — high iterations / blockers, from the state DB — rank higher). Fail-open.
set +e

QUERY="$1"; N="${2:-5}"
case "$N" in ''|*[!0-9]*) N=5 ;; esac
[ -z "$QUERY" ] && { echo "usage: cdt-recall \"<task or query>\" [N]"; exit 0; }

VAULT="${CDT_VAULT:-$HOME/.claude/vault}"
LEARN="$VAULT/learnings.md"
DB="${CDT_DB:-$HOME/.claude/claude-dev-team.db}"
[ -f "$LEARN" ] || exit 0

if command -v python3 >/dev/null 2>&1; then
  QUERY="$QUERY" N="$N" LEARN="$LEARN" DB="$DB" \
  CDT_RECALL_HALFLIFE_DAYS="${CDT_RECALL_HALFLIFE_DAYS:-}" \
  CDT_RECALL_RECENCY_WEIGHT="${CDT_RECALL_RECENCY_WEIGHT:-}" \
  CDT_RECALL_OUTCOME_WEIGHT="${CDT_RECALL_OUTCOME_WEIGHT:-}" \
  python3 - <<'PY'
import os, re, math, datetime, sqlite3
query = os.environ.get("QUERY", "")
try:
    n = max(1, int(os.environ.get("N", "5") or 5))
except ValueError:
    n = 5
path = os.environ.get("LEARN", "")

def envf(name, default):
    try:
        v = float(os.environ.get(name, "") or default)
        return v
    except ValueError:
        return default

HALF = max(1.0, envf("CDT_RECALL_HALFLIFE_DAYS", 180.0))
WR = envf("CDT_RECALL_RECENCY_WEIGHT", 2.0)
WO = envf("CDT_RECALL_OUTCOME_WEIGHT", 1.5)

STOP = set("the a an and or of to in is for on with by it this that be are as at from "
           "your you our we i if then so not no run use used using when where what how".split())

def toks(s):
    return [t for t in re.split(r"[^a-z0-9]+", s.lower()) if len(t) > 2 and t not in STOP]

qt = toks(query)
if not qt:
    raise SystemExit(0)            # no usable query terms — nothing to rank on
qset = set(qt)

# OUTCOME signal: term -> accumulated "pain" from past tasks (iterations + 3 if blocked/deferred).
pain = {}
db = os.environ.get("DB", "")
if db and os.path.exists(db):
    try:
        con = sqlite3.connect(db)
        for desc, status, iters in con.execute(
                "SELECT description, status, iterations FROM tasks WHERE description IS NOT NULL"):
            w = (iters if isinstance(iters, int) else 0) + \
                (3 if (status or "").lower() in ("blocker", "deferred") else 0)
            if w <= 0:
                continue
            for t in set(toks(desc or "")) & qset:     # only query-relevant terms matter
                pain[t] = pain.get(t, 0) + w
        con.close()
    except Exception:
        pass

try:
    today = datetime.date.today()
except Exception:
    today = None

scored = []
try:
    for raw in open(path, encoding="utf-8", errors="ignore"):
        s = raw.strip()
        if not s.startswith("- ["):  # only real learning bullets: "- [YYYY-MM-DD] ..."
            continue
        lt = toks(s)
        if not lt:
            continue
        base = sum(lt.count(t) for t in qt)            # lexical term overlap
        if base == 0:
            continue                                   # not relevant — recency/outcome only RE-RANK
        low = s.lower()
        score = float(base)
        for i in range(len(qt) - 1):                   # phrase bonus for adjacent query terms
            if f"{qt[i]} {qt[i+1]}" in low:
                score += 2
        m = re.match(r"- \[(\d{4})-(\d{2})-(\d{2})\]", s)   # recency boost
        if m and today is not None:
            try:
                d = datetime.date(int(m.group(1)), int(m.group(2)), int(m.group(3)))
                days = max(0, (today - d).days)
                score += WR * (0.5 ** (days / HALF))
            except Exception:
                pass
        oscore = sum(pain.get(t, 0) for t in (set(lt) & qset))   # outcome boost (bounded via log)
        if oscore > 0:
            score += WO * min(3.0, math.log1p(oscore))
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

# Read-back: append relevant notes from the Obsidian vault (your curated knowledge), fail-open.
# cdt-obsidian recall self-gates — it prints nothing when Obsidian is disabled/unconfigured.
for _obs in "$(dirname "$0")/cdt-obsidian" "$(dirname "$0")/obsidian.sh"; do
  [ -f "$_obs" ] && { bash "$_obs" recall "$QUERY" "$N" 2>/dev/null; break; }
done
exit 0
