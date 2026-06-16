#!/usr/bin/env bash
# scope-lib.sh — shared scope/sprawl-detection logic (Phase 3). Sourced (never executed) by
# agent-track.sh (SubagentStop) and contract.sh (cdt-contract). Detects when a subagent wrote files
# OUTSIDE its exclusive-file contract (overreach) or INTO a peer's scope (collision). Fail-open.
#
# Contracts live at:  ~/.claude/.cdt/contracts/<session_id>/{pending,claimed}/<seq>__<agent>.json
#   { "exclusive": ["api/**"], "read": ["types/**"], "agent_type": "...", "cwd": "...", ... }
#
# Public API:
#   cdt_scope_dir <session_id>                 -> path of the session's contracts dir
#   cdt_scope_claim <session_id> <agent_type>  -> atomically claim (mv pending->claimed) the oldest
#                                                 matching contract; echo its path, or non-zero if none
#   cdt_scope_eval                             -> reads CDT_TRANSCRIPT / CDT_OWN / CDT_SESSION_DIR /
#                                                 CDT_AGENT / CDT_CWD; prints findings as JSON lines

cdt_scope_dir() { printf '%s/.claude/.cdt/contracts/%s' "$HOME" "${1:-default}"; }

# Atomically claim this agent's oldest pending contract. POSIX rename is atomic, so under concurrent
# SubagentStop waves a losing mv just falls through to the next candidate — no lock needed.
cdt_scope_claim() {
  local sid="$1" agent="$2" dir san f base
  dir="$(cdt_scope_dir "$sid")"
  [ -d "$dir/pending" ] || return 1
  san="$(printf '%s' "$agent" | tr '/:' '--')"
  mkdir -p "$dir/claimed" 2>/dev/null
  # Bash expands globs in sorted order, and filenames are timestamp-prefixed, so this is oldest-first.
  for f in "$dir"/pending/*__"$san".json; do
    [ -e "$f" ] || continue
    base="$(basename "$f")"
    if mv "$f" "$dir/claimed/$base" 2>/dev/null; then
      printf '%s\n' "$dir/claimed/$base"
      return 0
    fi
  done
  return 1
}

cdt_scope_eval() {
  command -v python3 >/dev/null 2>&1 || return 0
  python3 - <<'PY'
import os, sys, json, re, fnmatch, glob as globmod

def load(p):
    try:
        return json.load(open(p))
    except Exception:
        return {}

own = load(os.environ.get("CDT_OWN", ""))
own_excl = own.get("exclusive") or []
agent = os.environ.get("CDT_AGENT", "") or own.get("agent_type", "")
cwd = (os.environ.get("CDT_CWD", "") or own.get("cwd", "")).rstrip("/")

# Files this subagent actually wrote, from its OWN transcript (parallel agents share one tree, so a
# git diff can't attribute a file to a specific agent — the transcript can).
touched = set()
try:
    with open(os.environ.get("CDT_TRANSCRIPT", ""), encoding="utf-8", errors="ignore") as fh:
        for line in fh:
            line = line.strip()
            if not line:
                continue
            try:
                o = json.loads(line)
            except Exception:
                continue
            content = (o.get("message") or {}).get("content")
            if not isinstance(content, list):
                continue
            for b in content:
                if isinstance(b, dict) and b.get("type") == "tool_use" \
                        and b.get("name") in ("Edit", "Write", "MultiEdit", "NotebookEdit"):
                    inp = b.get("input") or {}
                    fp = inp.get("file_path") or inp.get("notebook_path")
                    if fp:
                        touched.add(fp)
except Exception:
    pass

def rel(p):
    if cwd and p.startswith(cwd + "/"):
        return p[len(cwd) + 1:]
    return p.lstrip("/")

def in_scope(path, globs):
    for g in globs:
        g = (g or "").strip().rstrip("/")
        if not g:
            continue
        if fnmatch.fnmatch(path, g):          # fnmatch '*' spans '/', so this is lenient (fewer false +)
            return True
        if fnmatch.fnmatch(path, g + "/*"):
            return True
        base = re.sub(r"/\*\*?$", "", g)       # bare dir / prefix
        if base and (path == base or path.startswith(base + "/")):
            return True
    return False

# Peer contracts in this session (for collision detection).
others = []
own_file = os.path.abspath(os.environ.get("CDT_OWN", ""))
sd = os.environ.get("CDT_SESSION_DIR", "")
for sub in ("pending", "claimed"):
    for cf in globmod.glob(os.path.join(sd, sub, "*.json")):
        if os.path.abspath(cf) == own_file:
            continue
        c = load(cf)
        if c.get("exclusive"):
            others.append((c.get("agent_type") or os.path.basename(cf), c["exclusive"]))

for p in sorted(touched):
    rp = rel(p)
    owner = None
    for (oa, oexcl) in others:
        if in_scope(rp, oexcl):
            owner = oa
            break
    if owner is not None:
        print(json.dumps({"type": "collision", "agent": agent, "path": rp, "owner": owner}))
    elif own_excl and not in_scope(rp, own_excl):
        print(json.dumps({"type": "overreach", "agent": agent, "path": rp}))
sys.exit(0)
PY
}
