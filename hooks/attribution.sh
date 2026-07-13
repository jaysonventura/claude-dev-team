#!/usr/bin/env bash
# cdt-attribution — guarantee Claude Code adds NO AI attribution to git commits or PRs.
#
#   cdt-attribution            enforce (merge the keys into settings.json; silent when already compliant)
#   cdt-attribution --check    report only — never writes. exit 0 = compliant · exit 1 = would change
#
# WHY settings.json: the "Co-Authored-By: Claude" commit trailer, the "Generated with Claude Code" PR
# footer and the "Claude-Session: <url>" trailer are emitted because Claude Code injects an instruction
# into its own system prompt when attribution is enabled. Turning it off in Claude Code's settings is the
# ONLY real source of truth — a CLAUDE.md rule or a repo git hook can't guarantee it on every machine.
#
# Keys enforced in $CDT_SETTINGS (default ~/.claude/settings.json):
#   "includeCoAuthoredBy": false                                   (deprecated but still honored)
#   "attribution": { "commit": "", "pr": "", "sessionUrl": false } (current API — "" hides that attribution)
#
# Knob: CDT_NO_AI_ATTRIBUTION (default 1 = enforce; 0/off/false/no = no-op). Resolved env-first, then the
# CDT env file — which is READ WITH grep, never sourced (a crafted value must never execute).
#
# Safety contract: fail-open. Never blocks session start, never corrupts settings.json (a file that does
# not parse as a JSON object is left untouched), never rewrites a compliant file, preserves every other
# key, and writes atomically (temp file in the same dir + os.replace).
set +e

CDT_HOME="${CDT_HOME:-$HOME/.claude}"
ENV_FILE="${CDT_ENV_FILE:-$CDT_HOME/claude-dev-team.env}"
SETTINGS="${CDT_SETTINGS:-$CDT_HOME/settings.json}"

usage() {
  echo "usage: cdt-attribution [--check]"
  echo "  (no args)  enforce no-AI-attribution in $SETTINGS (silent when already compliant)"
  echo "  --check    report only, never writes — exit 0 = compliant, exit 1 = would change"
  echo "  knob: CDT_NO_AI_ATTRIBUTION=0 disables enforcement (cdt-config attribution off)"
}

MODE="apply"
case "${1:-}" in
  ""|--apply|apply)   MODE="apply" ;;
  --check|check)      MODE="check" ;;
  -h|--help|help)     usage; exit 0 ;;
  *) usage; exit 0 ;;
esac

# Resolve a knob: process env wins when set and non-empty, else the CDT env file, else the default.
# grep + cut — NEVER `source` the env file.
cfg() {
  local var="$1" def="$2" val
  val="${!var-}"
  [ -n "$val" ] && { printf '%s\n' "$val"; return 0; }
  val="$(grep -E "^${var}=" "$ENV_FILE" 2>/dev/null | head -1 | cut -d= -f2-)"
  [ -n "$val" ] && { printf '%s\n' "$val"; return 0; }
  printf '%s\n' "$def"
}

KNOB="$(cfg CDT_NO_AI_ATTRIBUTION 1)"
case "$(printf '%s' "$KNOB" | tr '[:upper:]' '[:lower:]' | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')" in
  0|off|false|no)
    [ "$MODE" = "check" ] && echo "cdt-attribution: enforcement OFF (CDT_NO_AI_ATTRIBUTION=$KNOB) — settings.json not inspected."
    exit 0 ;;
esac

# python3 is the only way we touch JSON (no sed/awk surgery on the user's settings). Absent → quiet no-op.
command -v python3 >/dev/null 2>&1 || {
  [ "$MODE" = "check" ] && echo "cdt-attribution: python3 not found — cannot verify settings.json (run: cdt-deps --install)"
  exit 0
}

MODE="$MODE" SETTINGS="$SETTINGS" python3 - <<'PY'
import json, os, sys, tempfile

path = os.environ["SETTINGS"]
mode = os.environ["MODE"]          # "apply" | "check"

# The four keys that must hold. sessionUrl/includeCoAuthoredBy are booleans; "" hides that attribution.
WANT_COAUTH = False
WANT_ATTR   = {"commit": "", "pr": "", "sessionUrl": False}

def bail(msg, code):
    print(msg)
    sys.exit(code)

if os.path.exists(path):
    try:
        with open(path) as f:
            data = json.load(f)
    except Exception:
        # Do NOT write. A settings.json we can't parse is a settings.json we must not destroy.
        bail("cdt-attribution: %s is not valid JSON — NOT modified. Fix it, then re-run: cdt-attribution" % path,
             1 if mode == "check" else 0)
    if not isinstance(data, dict):
        bail("cdt-attribution: %s is not a JSON object — NOT modified." % path,
             1 if mode == "check" else 0)
else:
    data = {}

def is_wrong(cur, want):
    """Strict: a JSON `false` is not `0`, and a JSON `""` is not `false`. Missing (None) is always wrong."""
    if isinstance(want, bool):
        return cur is not want                           # identity — rejects 0/1/"false"/None
    return isinstance(cur, bool) or cur != want          # string want — rejects booleans and None

# What is wrong right now?
attr = data.get("attribution")
attr = dict(attr) if isinstance(attr, dict) else {}      # preserve any sub-keys we don't manage
wrong = []
if is_wrong(data.get("includeCoAuthoredBy"), WANT_COAUTH):
    wrong.append("includeCoAuthoredBy")
for k, v in WANT_ATTR.items():
    if is_wrong(attr.get(k), v):
        wrong.append("attribution.%s" % k)

if not wrong:
    # Already correct: write NOTHING (no churn — this runs on every SessionStart).
    if mode == "check":
        print("cdt-attribution: compliant — no Co-Authored-By / Generated-with / session trailer will be added.")
    sys.exit(0)

if mode == "check":
    print("cdt-attribution: NOT enforced in %s — would set: %s" % (path, ", ".join(wrong)))
    sys.exit(1)

# ---- apply: merge (every other top-level key and every unmanaged attribution sub-key survives) ----
data["includeCoAuthoredBy"] = WANT_COAUTH
attr.update(WANT_ATTR)
data["attribution"] = attr

# Resolve symlinks so a dotfiles-managed settings.json (chezmoi/stow) is edited in place through the
# link, not replaced by a regular file that silently diverges from the dotfiles source.
path = os.path.realpath(path)
d_dir = os.path.dirname(path) or "."
try:
    os.makedirs(d_dir, exist_ok=True)
except Exception:
    pass
try:
    mode_bits = os.stat(path).st_mode & 0o777 if os.path.exists(path) else None
except Exception:
    mode_bits = None

# mkstemp is inside the try so an unwritable dir / full disk bails gracefully instead of dumping a
# traceback (still rc=0, but noisy — e.g. via `cdt-config attribution on`).
tmp = None
try:
    fd, tmp = tempfile.mkstemp(dir=d_dir)
    with os.fdopen(fd, "w") as f:
        json.dump(data, f, indent=2)
        f.write("\n")
    if mode_bits is not None:
        os.chmod(tmp, mode_bits)                          # keep the user's original permissions
    os.replace(tmp, path)                                 # atomic
except Exception as e:
    if tmp is not None:
        try:
            os.unlink(tmp)
        except OSError:
            pass
    bail("cdt-attribution: could not write %s (%s) — left unchanged." % (path, e), 0)

print("cdt-attribution: no-AI-attribution enforced in settings.json (set: %s) — applies next session."
      % ", ".join(wrong))
sys.exit(0)
PY
rc=$?

# --check reports (0 compliant / 1 would change). Enforcement itself is ALWAYS fail-open.
[ "$MODE" = "check" ] && exit "$rc"
exit 0
