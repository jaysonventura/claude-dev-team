#!/usr/bin/env bash
# verify-lib.sh — shared "is this a verifying command?" logic for the verification gate.
# Sourced (never executed) by:
#   - verify-track.sh   (PostToolUse Bash)  — marks the session "verified" when a test/build/lint runs
#   - agent-track.sh    (SubagentStop)      — marks "verified" when a SUBAGENT ran one (the qa-engineer flow)
#   - completion-guard.sh (Stop)            — blocks/warns if edits happened with no verify afterward
# Pure-stdlib python3 with a coarse grep fallback. Callers are fail-open: any error is treated as "no".
#
# Public API:
#   cdt_edit_marker   <session_id>   -> path of the "edits happened" marker (written by format-on-write.sh)
#   cdt_verify_marker <session_id>   -> path of the "verified" marker (written by this gate's hooks)
#   cdt_verify_match  "<command>"    -> exit 0 if the shell command runs a test/build/lint/typecheck
#   cdt_verify_scan_transcript <path>-> exit 0 if the JSONL transcript contains such a Bash command
#   cdt_verify_payload_mark          -> reads CDT_PAYLOAD + CDT_REQUIRE_OUTPUT; exit 0 = should mark verified

cdt_edit_marker()   { printf '%s/cdt-edits-%s.marker'    "${TMPDIR:-/tmp}" "${1:-default}"; }
cdt_verify_marker() { printf '%s/cdt-verified-%s.marker' "${TMPDIR:-/tmp}" "${1:-default}"; }

# Coarse, verb-anchored grep used only when python3 is unavailable. Conservative (favours not-marking).
_cdt_verify_grep() {
  printf '%s' "${1:-}" | grep -Eq \
'(^|[;&|]|&&|\|\|)[[:space:]]*((sudo|env|time|nice|exec|command)[[:space:]]+)*([A-Za-z_][A-Za-z0-9_]*=[^[:space:]]*[[:space:]]+)*((npm|pnpm|yarn|bun)[[:space:]]+(run[[:space:]]+)?(test|lint|typecheck|tsc|build|check|ci|e2e|coverage|verify|validate|spec)|npx[[:space:]]+(jest|vitest|mocha|tsc|eslint|biome|playwright)|pytest|py\.test|tox|nose2|jest|vitest|mocha|ava|rspec|rubocop|phpunit|phpstan|eslint|biome|ruff|flake8|pylint|mypy|pyright|tsc|swiftlint|ctest|rake|vite|webpack|rollup|tsup|make([[:space:]]|$)|go[[:space:]]+(test|vet|build)|cargo[[:space:]]+(test|build|check|clippy|nextest|bench)|swift[[:space:]]+(test|build)|dotnet[[:space:]]+(test|build)|bazel[[:space:]]+(test|build)|(gradle|\./gradlew|mvn|\./mvnw)[[:space:]]|xcodebuild|cmake|python[0-9.]*[[:space:]]+-m[[:space:]]+(pytest|unittest|mypy|pylint|ruff|flake8|tox|nose2)))' \
    && return 0
  return 1
}

# The embedded matcher/scanner. argv[1] = mode (match|scan|payload). Inputs come from env so stdin is
# free for the heredoc program. The 'PY' delimiter is quoted, so the body is fully literal.
cdt__verify_run() {
  python3 - "$1" <<'PY'
import os, sys, re, json

mode = sys.argv[1] if len(sys.argv) > 1 else "match"

# Single-token test/lint/build/typecheck verbs (a segment whose leading verb is one of these counts).
SINGLE = {
    "pytest", "py.test", "tox", "nose2", "jest", "vitest", "mocha", "ava", "jasmine", "karma",
    "rspec", "rubocop", "phpunit", "phpstan", "tsc", "mypy", "pyright", "flake8", "pylint", "ruff",
    "eslint", "biome", "golangci-lint", "clippy", "swiftlint", "ctest", "tsup", "rollup", "webpack",
    "vite", "rake", "playwright",
}
# npm/pnpm/yarn/bun run <script>: the script name must start with one of these.
SCRIPT_RE = re.compile(r"^(test|lint|typecheck|tsc|build|check|ci|e2e|coverage|verify|validate|spec|unit|integration)")
# leading wrappers to skip before the real verb.
WRAP = {"sudo", "env", "time", "nice", "exec", "command", "builtin", "stdbuf", "nohup"}
# build tools that only count as verification when paired with a build/test/check goal.
GOALS = {"test", "verify", "check", "build", "package", "integration-test", "lint", "e2e", "ci",
         "spec", "coverage", "typecheck", "all"}

def lead_tokens(seg):
    try:
        import shlex
        t = shlex.split(seg)
    except Exception:
        t = seg.split()
    i = 0
    while i < len(t):
        w = t[i]
        if re.match(r"^[A-Za-z_][A-Za-z0-9_]*=", w):   # FOO=bar prefix assignment
            i += 1; continue
        if w in WRAP:
            i += 1; continue
        break
    return t[i:]

def seg_is_verify(seg, depth=0):
    t = lead_tokens(seg)
    if not t:
        return False
    v = t[0]; rest = t[1:]
    base = v.rsplit("/", 1)[-1]          # ./gradlew -> gradlew
    if base in SINGLE:
        return True
    if base == "make":
        return True                       # building the project is a form of verification
    if base == "go":
        return bool(rest) and rest[0] in ("test", "vet", "build")
    if base == "cargo":
        return bool(rest) and rest[0] in ("test", "build", "check", "clippy", "nextest", "bench")
    if base == "swift":
        return bool(rest) and rest[0] in ("test", "build")
    if base == "dotnet":
        return bool(rest) and rest[0] in ("test", "build")
    if base == "bazel":
        return bool(rest) and rest[0] in ("test", "build")
    if base in ("gradle", "gradlew", "mvn", "mvnw"):
        return any(x in GOALS for x in rest)
    if base in ("xcodebuild", "cmake"):
        return True
    if base == "next":
        return bool(rest) and rest[0] in ("build", "lint")
    if base in ("deno", "rails"):
        return bool(rest) and rest[0] == "test"
    if base in ("npm", "pnpm", "yarn", "bun"):
        if rest and rest[0] == "run":
            return len(rest) > 1 and bool(SCRIPT_RE.match(rest[1]))
        return bool(rest) and rest[0] in (
            "test", "lint", "build", "typecheck", "check", "ci", "e2e", "coverage")
    if base == "npx":
        return depth == 0 and bool(rest) and seg_is_verify(" ".join(rest), depth + 1)
    if re.match(r"^python[0-9.]*$", base):
        return len(rest) >= 2 and rest[0] == "-m" and rest[1] in (
            "pytest", "unittest", "mypy", "pylint", "ruff", "flake8", "tox", "nose2")
    return False

def cmd_is_verify(cmd):
    if not cmd:
        return False
    for seg in re.split(r"&&|\|\||;|\|", cmd):       # split connectors; test each sub-command
        if seg_is_verify(seg):
            return True
    return False

if mode == "match":
    sys.exit(0 if cmd_is_verify(os.environ.get("CDT_VC", "")) else 1)

if mode == "scan":
    path = os.environ.get("CDT_TRANSCRIPT", "")
    try:
        with open(path, encoding="utf-8", errors="ignore") as fh:
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
                    if isinstance(b, dict) and b.get("type") == "tool_use" and b.get("name") == "Bash":
                        if cmd_is_verify((b.get("input") or {}).get("command", "")):
                            sys.exit(0)
        sys.exit(1)
    except Exception:
        sys.exit(1)

if mode == "payload":
    try:
        o = json.loads(os.environ.get("CDT_PAYLOAD", "") or "{}")
    except Exception:
        sys.exit(1)
    ti = o.get("tool_input") or {}
    cmd = ti.get("command", "") if isinstance(ti, dict) else ""
    if not cmd_is_verify(cmd):
        sys.exit(1)
    if os.environ.get("CDT_REQUIRE_OUTPUT", "1") == "1":
        resp = o.get("tool_response")
        s = resp if isinstance(resp, str) else json.dumps(resp)
        low = (s or "").lower()
        # a command that never actually ran shouldn't count as verification.
        if len(low) < 200 and ("command not found" in low or "no such file or directory" in low):
            sys.exit(1)
    sys.exit(0)

sys.exit(1)
PY
}

cdt_verify_match() {
  [ -n "${1:-}" ] || return 1
  if command -v python3 >/dev/null 2>&1; then
    export CDT_VC="$1"; cdt__verify_run match; local rc=$?; unset CDT_VC; return "$rc"
  fi
  _cdt_verify_grep "$1"
}

cdt_verify_scan_transcript() {
  [ -n "${1:-}" ] && [ -f "$1" ] || return 1
  command -v python3 >/dev/null 2>&1 || return 1
  export CDT_TRANSCRIPT="$1"; cdt__verify_run scan; local rc=$?; unset CDT_TRANSCRIPT; return "$rc"
}

cdt_verify_payload_mark() {   # caller exports CDT_PAYLOAD (+ optional CDT_REQUIRE_OUTPUT)
  command -v python3 >/dev/null 2>&1 || return 2
  cdt__verify_run payload
}
