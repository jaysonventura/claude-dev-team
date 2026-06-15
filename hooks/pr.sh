#!/usr/bin/env bash
# cdt-pr — a safe, read-mostly `gh` wrapper for the PR autopilot loop. It gives the orchestrator clean,
# structured access to a pull request's CI status, failing checks, diff, and mergeability, plus ONE
# benign write op (post a review comment).
#
# SAFETY: this tool NEVER pushes, force-pushes, merges, closes, or rebases. Code fixes + pushes are done
# by the orchestrator's engineer agents under the normal review gates; merging requires explicit human
# confirmation. The only state-changing command here is `comment` (posts a PR comment).
#
#   cdt-pr status  <PR> [owner/repo]            CI rollup: PASS/FAIL/PENDING + failing check names
#   cdt-pr checks  <PR> [owner/repo]            only the FAILING checks (name + url)
#   cdt-pr view    <PR> [owner/repo]            title, branch, mergeable state, conflict flag
#   cdt-pr diff    <PR> [owner/repo]            the PR diff (truncated to ~400 lines)
#   cdt-pr comment <PR> <body-file> [owner/repo] post a review comment from a file (the only write)
set +e

cmd="$1"; pr="$2"

command -v gh >/dev/null 2>&1 || { echo "cdt-pr: gh CLI not found (install: https://cli.github.com)"; exit 0; }
gh auth status >/dev/null 2>&1 || { echo "cdt-pr: gh not authenticated (run: gh auth login)"; exit 0; }
case "$cmd" in status|checks|view|diff|comment) : ;; *)
  echo "usage: cdt-pr {status|checks|view|diff|comment} <PR> [owner/repo]"; exit 0 ;; esac
case "$pr" in ''|*[!0-9]*) echo "cdt-pr: <PR> must be a number"; exit 0 ;; esac
# status/checks/view parse gh's JSON with python3; fail with a clear message if it's absent
# (diff/comment don't need it).
case "$cmd" in status|checks|view)
  command -v python3 >/dev/null 2>&1 || { echo "cdt-pr: python3 required to parse '$cmd' output (not found)"; exit 0; } ;;
esac

# Resolve optional owner/repo into a gh args array (avoids word-splitting / SC2086).
repo_args=()
if [ "$cmd" = "comment" ]; then
  body="$3"; [ -n "$4" ] && repo_args=(-R "$4")
else
  [ -n "$3" ] && repo_args=(-R "$3")
fi

case "$cmd" in
  status)
    OUT="$(gh pr view "$pr" "${repo_args[@]}" --json state,mergeable,mergeStateStatus,statusCheckRollup 2>/dev/null)" \
    python3 - <<'PY'
import os, json
try:
    d = json.loads(os.environ.get("OUT", "") or "")
except Exception:
    d = None
if not d:
    print("cdt-pr: could not read PR (check the number / repo / access)"); raise SystemExit(0)
roll = d.get("statusCheckRollup") or []
def concl(c): return (c.get("conclusion") or c.get("state") or c.get("status") or "").upper()
fail = [c for c in roll if concl(c) in ("FAILURE", "ERROR", "CANCELLED", "TIMED_OUT")]
pend = [c for c in roll if concl(c) in ("PENDING", "IN_PROGRESS", "QUEUED", "")]
overall = "FAIL" if fail else ("PENDING" if pend else ("PASS" if roll else "NO-CHECKS"))
print(f"CI: {overall}  ({len(roll)} checks: {len(fail)} failing, {len(pend)} pending)")
print(f"mergeable: {d.get('mergeable','?')}  state: {d.get('mergeStateStatus','?')}")
for c in fail[:10]:
    print(f"  FAIL  {c.get('name') or c.get('context') or '?'}")
PY
    ;;
  checks)
    OUT="$(gh pr view "$pr" "${repo_args[@]}" --json statusCheckRollup 2>/dev/null)" \
    python3 - <<'PY'
import os, json
try:
    roll = (json.loads(os.environ.get("OUT", "") or "") or {}).get("statusCheckRollup") or []
except Exception:
    raise SystemExit(0)
def concl(c): return (c.get("conclusion") or c.get("state") or "").upper()
fails = [c for c in roll if concl(c) in ("FAILURE", "ERROR", "CANCELLED", "TIMED_OUT")]
if not fails:
    print("no failing checks"); raise SystemExit(0)
for c in fails:
    print(f"FAIL  {c.get('name') or c.get('context') or '?'}  {c.get('detailsUrl') or ''}")
PY
    ;;
  view)
    OUT="$(gh pr view "$pr" "${repo_args[@]}" --json number,title,mergeable,mergeStateStatus,isDraft,headRefName 2>/dev/null)" \
    python3 - <<'PY'
import os, json
try:
    d = json.loads(os.environ.get("OUT", "") or "")
except Exception:
    d = None
if not d:
    print("cdt-pr: could not read PR"); raise SystemExit(0)
print(f"#{d.get('number')} {d.get('title','')}")
print(f"branch: {d.get('headRefName','?')}  draft: {d.get('isDraft')}")
m = d.get('mergeable', '?')
print(f"mergeable: {m}" + ("  CONFLICTS — needs resolution" if m == "CONFLICTING" else ""))
PY
    ;;
  diff)
    gh pr diff "$pr" "${repo_args[@]}" 2>/dev/null | head -n 400
    ;;
  comment)
    [ -f "$body" ] || { echo "cdt-pr: comment body file not found: $body"; exit 0; }
    gh pr comment "$pr" "${repo_args[@]}" --body-file "$body" 2>/dev/null \
      && echo "cdt-pr: review comment posted to PR #$pr" \
      || echo "cdt-pr: failed to post comment (check access)"
    ;;
esac
exit 0
