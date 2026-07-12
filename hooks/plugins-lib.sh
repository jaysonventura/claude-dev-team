#!/usr/bin/env bash
# plugins-lib.sh — shared, SOURCED library for the CDT plugin-bootstrap subsystem (v1.59.0).
#
# Detects which Claude Code plugins are installed / enabled and probes their dependencies, driven by the
# read-only registry at config/plugins.json (or a user copy). Callers (plugins.sh, plugin-route.sh, tests)
# use ONLY the frozen functions below — signatures are contractual, do not rename.
#
# House rules (match config.sh / usage-lib.sh / db.sh):
#   • STRICTLY fail-open — a missing/corrupt ~/.claude file yields an empty result + rc1, never a crash.
#   • NEVER print a raw token (see plib_redact).
#   • All state writes are atomic (mktemp+mv / python3 os.replace) and jailed to ~/.claude/.cdt/.
#   • No network. Idempotent. `set -u`-safe when sourced (every expansion has a default).
#
# Frozen interface:
#   plib_registry_path            plib_load_registry           plib_installed
#   plib_is_installed <id>        plib_is_enabled <id>         plib_marketplaces
#   plib_has_marketplace <name>   plib_probe_cli <bin>...      plib_get_env <k> / plib_set_env <k> <v>
#   plib_cfg <VAR> <DEFAULT>      plib_state_get <id> / plib_state_set <id> <enabled|disabled|manual|auto>
#   plib_redact                   plib_detect_signals <repo>   plib_emit_json <shell_fn_name>

CDT_HOME="${CDT_HOME:-$HOME/.claude}"
CDT_STATE_DIR="${CDT_STATE_DIR:-$CDT_HOME/.cdt}"                      # jail for all our writes
CDT_PLUGINS_STATE="${CDT_PLUGINS_STATE:-$CDT_STATE_DIR/plugins-state.json}"
CDT_PLUGINS_REGISTRY_LOCAL="${CDT_PLUGINS_REGISTRY_LOCAL:-$CDT_STATE_DIR/plugins-registry.json}"
CDT_PLUGINS_ENV="${CDT_ENV_FILE:-$CDT_HOME/claude-dev-team.env}"      # same env file config.sh upserts
CDT_PLUGINS_SETTINGS="${CDT_SETTINGS:-$CDT_HOME/settings.json}"

# Resolve the repo root from this file's own location (hooks/plugins-lib.sh -> repo/), so the shipped
# registry can be found regardless of the caller's cwd.
_plib_self="${BASH_SOURCE[0]:-$0}"
_plib_dir="$(cd "$(dirname "$_plib_self")" 2>/dev/null && pwd)"
_PLIB_REPO="$(cd "${_plib_dir:-.}/.." 2>/dev/null && pwd)"
[ -n "${_PLIB_REPO:-}" ] || _PLIB_REPO="."

_plib_py() { command -v python3 >/dev/null 2>&1; }

# plib_registry_path — echo the active registry path: $CDT_PLUGIN_REGISTRY override, else a user copy at
# ~/.claude/.cdt/plugins-registry.json if present, else the shipped <repo>/config/plugins.json.
plib_registry_path() {
  if [ -n "${CDT_PLUGIN_REGISTRY:-}" ]; then
    printf '%s\n' "$CDT_PLUGIN_REGISTRY"; return 0
  fi
  if [ -f "$CDT_PLUGINS_REGISTRY_LOCAL" ]; then
    printf '%s\n' "$CDT_PLUGINS_REGISTRY_LOCAL"; return 0
  fi
  printf '%s\n' "$_PLIB_REPO/config/plugins.json"
}

# plib_load_registry — cat the registry after json-validating it via python3. Prints nothing + rc1 on a
# read/parse error (fail-open). If python3 is unavailable we cat best-effort (can't validate) + rc0.
plib_load_registry() {
  local p; p="$(plib_registry_path)"
  [ -f "$p" ] || return 1
  if command -v python3 >/dev/null 2>&1; then
    if CDT_RP="$p" python3 -c 'import json,os; json.load(open(os.environ["CDT_RP"]))' >/dev/null 2>&1; then
      cat "$p" 2>/dev/null; return 0
    fi
    return 1
  fi
  cat "$p" 2>/dev/null; return 0
}

# plib_installed — emit "id<TAB>version<TAB>scope" for each INSTALLED plugin that maps to a registry id.
# Source: ~/.claude/plugins/installed_plugins.json  ({"version":2,"plugins":{"<name>@<mkt>":[{...}]}}).
# The "<name>@<mkt>" key is matched against each registry row's installIdentifier to resolve the CDT id.
plib_installed() {
  _plib_py || return 1
  local reg inst; reg="$(plib_registry_path)"; inst="$CDT_HOME/plugins/installed_plugins.json"
  [ -f "$inst" ] || return 1
  CDT_RP="$reg" CDT_INST="$inst" python3 - <<'PY'
import json, os, sys
try:
    reg = json.load(open(os.environ["CDT_RP"]))
except Exception:
    reg = {}
by_ident = {}
for p in (reg.get("plugins", []) if isinstance(reg, dict) else []):
    if not isinstance(p, dict):
        continue
    ident = p.get("installIdentifier")
    if ident:
        by_ident[ident] = p.get("id")
try:
    inst = json.load(open(os.environ["CDT_INST"]))
except Exception:
    sys.exit(1)
plugins = inst.get("plugins", {}) if isinstance(inst, dict) else {}
out = []
for key, rows in (plugins.items() if isinstance(plugins, dict) else []):
    pid = by_ident.get(key)
    if not pid:
        continue
    row = {}
    if isinstance(rows, list) and rows and isinstance(rows[0], dict):
        row = rows[0]
    elif isinstance(rows, dict):
        row = rows
    ver = str(row.get("version", "") or "")
    scope = str(row.get("scope", "") or "")
    out.append("%s\t%s\t%s" % (pid, ver, scope))
if out:
    sys.stdout.write("\n".join(out) + "\n")
sys.exit(0)
PY
}

# plib_is_installed <id> — rc 0/1.
plib_is_installed() {
  local id="${1:-}"; [ -n "$id" ] || return 1
  plib_installed 2>/dev/null | cut -f1 | grep -Fxq "$id"
}

# plib_is_enabled <id> — rc 0/1. True iff settings.json enabledPlugins["<installIdentifier>"] (or the raw
# id, for registry rows without an installIdentifier) is exactly boolean true.
plib_is_enabled() {
  local id="${1:-}"; [ -n "$id" ] || return 1
  _plib_py || return 1
  local reg; reg="$(plib_registry_path)"
  [ -f "$CDT_PLUGINS_SETTINGS" ] || return 1
  CDT_RP="$reg" CDT_SET="$CDT_PLUGINS_SETTINGS" CDT_ID="$id" python3 - <<'PY'
import json, os, sys
rid = os.environ["CDT_ID"]
try:
    reg = json.load(open(os.environ["CDT_RP"]))
except Exception:
    reg = {}
ident = None
for p in (reg.get("plugins", []) if isinstance(reg, dict) else []):
    if isinstance(p, dict) and p.get("id") == rid:
        ident = p.get("installIdentifier"); break
try:
    st = json.load(open(os.environ["CDT_SET"]))
except Exception:
    sys.exit(1)
ep = st.get("enabledPlugins", {}) if isinstance(st, dict) else {}
keys = [k for k in (ident, rid) if k]
sys.exit(0 if any(ep.get(k) is True for k in keys) else 1)
PY
}

# plib_marketplaces — print each known marketplace name (fail-open empty).
plib_marketplaces() {
  _plib_py || return 1
  local f="$CDT_HOME/plugins/known_marketplaces.json"
  [ -f "$f" ] || return 1
  CDT_MK="$f" python3 - <<'PY'
import json, os, sys
try:
    d = json.load(open(os.environ["CDT_MK"]))
except Exception:
    sys.exit(1)
if not isinstance(d, dict):
    sys.exit(1)
for k in d.keys():
    print(k)
sys.exit(0)
PY
}

# plib_has_marketplace <name> — rc 0/1.
plib_has_marketplace() {
  local n="${1:-}"; [ -n "$n" ] || return 1
  plib_marketplaces 2>/dev/null | grep -Fxq "$n"
}

# plib_probe_cli <bin>... — rc0 iff ALL given binaries are on PATH; prints each MISSING one to stderr.
plib_probe_cli() {
  local missing=0 b
  for b in "$@"; do
    [ -n "$b" ] || continue
    if ! command -v "$b" >/dev/null 2>&1; then
      printf '%s\n' "$b" >&2
      missing=1
    fi
  done
  return "$missing"
}

# plib_get_env <k> — read a value from the CDT env file (fail-open empty).
plib_get_env() {
  local k="${1:-}"; [ -n "$k" ] || return 1
  [ -f "$CDT_PLUGINS_ENV" ] || return 1
  grep -E "^${k}=" "$CDT_PLUGINS_ENV" 2>/dev/null | head -1 | cut -d= -f2-
}

# plib_cfg <VAR> <DEFAULT> — resolve a CDT config knob the way statusline.sh / budget.sh do: the process
# env wins when the var is SET (non-empty); else the value persisted in the CDT env file (plib_get_env);
# else DEFAULT. Standalone hook subprocesses don't always inherit these exports, so the env file is the
# source of truth for cdt-config toggles. Always prints exactly one line; fail-open, set -u-safe.
plib_cfg() {
  local var="${1:-}" def="${2:-}" val
  [ -n "$var" ] || { printf '%s\n' "$def"; return 0; }
  val="${!var-}"
  [ -n "$val" ] && { printf '%s\n' "$val"; return 0; }
  val="$(plib_get_env "$var" 2>/dev/null)"
  [ -n "$val" ] && { printf '%s\n' "$val"; return 0; }
  printf '%s\n' "$def"
}

# plib_set_env <k> <v> — atomic upsert into the CDT env file (same pattern as config.sh set_env: strip the
# old line, append the new one via a temp file, mv into place, chmod 600).
plib_set_env() {
  local k="${1:-}" v="${2:-}" tmp
  [ -n "$k" ] || return 1
  mkdir -p "$(dirname "$CDT_PLUGINS_ENV")" 2>/dev/null || true
  [ -f "$CDT_PLUGINS_ENV" ] || : > "$CDT_PLUGINS_ENV"
  tmp="$(mktemp 2>/dev/null || echo "$CDT_PLUGINS_ENV.tmp.$$")"
  grep -v -E "^${k}=" "$CDT_PLUGINS_ENV" 2>/dev/null > "$tmp"
  printf '%s=%s\n' "$k" "$v" >> "$tmp"
  mv "$tmp" "$CDT_PLUGINS_ENV" 2>/dev/null || { rm -f "$tmp" 2>/dev/null; return 1; }
  chmod 600 "$CDT_PLUGINS_ENV" 2>/dev/null || true
}

# plib_state_get <id> — resolve a plugin's effective state. Overlay value if set, else the registry
# default (enabledByDefault: true->auto, false->disabled). rc1 if the id is unknown to the registry.
plib_state_get() {
  local id="${1:-}"; [ -n "$id" ] || return 1
  _plib_py || return 1
  local reg; reg="$(plib_registry_path)"
  CDT_STATE="$CDT_PLUGINS_STATE" CDT_RP="$reg" CDT_ID="$id" python3 - <<'PY'
import json, os, sys
rid = os.environ["CDT_ID"]
sp = os.environ["CDT_STATE"]
try:
    d = json.load(open(sp)) if os.path.exists(sp) else {}
except Exception:
    d = {}
if isinstance(d, dict) and isinstance(d.get(rid), str):
    print(d[rid]); sys.exit(0)
try:
    reg = json.load(open(os.environ["CDT_RP"]))
except Exception:
    reg = {}
for p in (reg.get("plugins", []) if isinstance(reg, dict) else []):
    if isinstance(p, dict) and p.get("id") == rid:
        print("auto" if p.get("enabledByDefault") else "disabled"); sys.exit(0)
print("disabled"); sys.exit(1)
PY
}

# plib_state_set <id> <enabled|disabled|manual|auto> — write a per-plugin override into the overlay at
# ~/.claude/.cdt/plugins-state.json. Creates the dir, backs up .bak before modify, writes atomically.
plib_state_set() {
  local id="${1:-}" state="${2:-}"
  [ -n "$id" ] || return 1
  case "$state" in enabled|disabled|manual|auto) ;; *) return 1 ;; esac
  _plib_py || return 1
  mkdir -p "$CDT_STATE_DIR" 2>/dev/null || true
  chmod 700 "$CDT_STATE_DIR" 2>/dev/null || true
  CDT_STATE="$CDT_PLUGINS_STATE" CDT_ID="$id" CDT_VAL="$state" python3 - <<'PY'
import json, os, sys, tempfile, shutil
p = os.environ["CDT_STATE"]; rid = os.environ["CDT_ID"]; val = os.environ["CDT_VAL"]
try:
    d = json.load(open(p)) if os.path.exists(p) else {}
    if not isinstance(d, dict):
        d = {}
except Exception:
    d = {}
try:
    if os.path.exists(p):
        shutil.copy2(p, p + ".bak")
except Exception:
    pass
d[rid] = val
dd = os.path.dirname(p) or "."
tmp = None
try:
    fd, tmp = tempfile.mkstemp(dir=dd)
    with os.fdopen(fd, "w") as f:
        json.dump(d, f, indent=2); f.write("\n")
    os.replace(tmp, p)
    try:
        os.chmod(p, 0o600)
    except OSError:
        pass
except Exception:
    if tmp:
        try: os.unlink(tmp)
        except OSError: pass
    sys.exit(1)
sys.exit(0)
PY
}

# plib_redact — stdin->stdout filter that masks common token/key/PAT/secret patterns. python3 primary
# (portable regex, incl. macOS BSD where `sed I` is unsupported); sed fallback; cat as last resort.
# NB: the program is captured into a var and run via `python3 -c` so stdin stays the caller's pipe
# (a heredoc `python3 - <<PY` would make the program itself stdin and drop the piped data).
plib_redact() {
  if command -v python3 >/dev/null 2>&1; then
    local _prog
    _prog="$(cat <<'PY'
import sys, re
pats = [
    (re.compile(r'(gh[opusr]_)[A-Za-z0-9]{16,}'), r'\1***REDACTED***'),
    (re.compile(r'github_pat_[A-Za-z0-9_]{20,}'), 'github_pat_***REDACTED***'),
    (re.compile(r'sk-[A-Za-z0-9_-]{16,}'), 'sk-***REDACTED***'),
    (re.compile(r'xox[baprs]-[A-Za-z0-9-]{10,}'), 'xox-***REDACTED***'),
    (re.compile(r'(?i)(bearer\s+)[A-Za-z0-9._~+/-]+=*'), r'\1***REDACTED***'),
    (re.compile(r'eyJ[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{4,}'), '***REDACTED_JWT***'),
    (re.compile(r'(?i)("?(?:token|secret|password|passwd|access[_-]?token|refresh[_-]?token|client[_-]?secret|api[_-]?key)"?\s*[:=]\s*"?)[^"\s,}]+'), r'\1***REDACTED***'),
]
for line in sys.stdin:
    for rx, repl in pats:
        line = rx.sub(repl, line)
    sys.stdout.write(line)
PY
)"
    python3 -c "$_prog"
  elif command -v sed >/dev/null 2>&1; then
    sed -E \
      -e 's/(gh[opusr]_)[A-Za-z0-9]{16,}/\1***REDACTED***/g' \
      -e 's/github_pat_[A-Za-z0-9_]{20,}/github_pat_***REDACTED***/g' \
      -e 's/sk-[A-Za-z0-9_-]{16,}/sk-***REDACTED***/g' \
      -e 's/([Bb]earer )[A-Za-z0-9._~+/-]+/\1***REDACTED***/g' 2>/dev/null || cat
  else
    cat
  fi
}

# plib_detect_signals <repo_dir> — echo each registry repoSignal glob that matches a file/dir in the tree
# (one token per line). Handles "<dir>/**" directory signals, "**/*.ext" recursive-extension globs, and
# bare filename globs (matched by basename at any depth, so e.g. menubar/Package.swift fires "Package.swift").
plib_detect_signals() {
  local dir="${1:-.}"
  [ -d "$dir" ] || return 1
  _plib_py || return 1
  local reg; reg="$(plib_registry_path)"
  CDT_RP="$reg" CDT_DIR="$dir" python3 - <<'PY'
import json, os, sys, fnmatch
root = os.environ["CDT_DIR"]
try:
    reg = json.load(open(os.environ["CDT_RP"]))
except Exception:
    sys.exit(1)
sigs, seen = [], set()
for p in (reg.get("plugins", []) if isinstance(reg, dict) else []):
    if not isinstance(p, dict):
        continue
    for s in ((p.get("activationRules") or {}).get("repoSignals") or []):
        if s and s not in seen:
            seen.add(s); sigs.append(s)

PRUNE = {'.git', 'node_modules', '.build', 'build', 'dist', 'DerivedData', 'vendor',
         '.venv', 'venv', '.next', '.svelte-kit', 'Pods', '.terraform', 'coverage', '__pycache__'}
files_base, files_rel, dirs_rel, dirs_base = set(), [], set(), set()
count, CAP = 0, 200000
for dp, dns, fns in os.walk(root):
    dns[:] = [d for d in dns if d not in PRUNE]
    rel = os.path.relpath(dp, root)
    if rel != '.':
        rp = rel.replace(os.sep, '/')
        dirs_rel.add(rp); dirs_base.add(rp.split('/')[-1])
    for fn in fns:
        count += 1
        if count > CAP:
            break
        frel = os.path.normpath(os.path.join(rel, fn)).replace(os.sep, '/')
        if frel.startswith('./'):
            frel = frel[2:]
        files_rel.append(frel); files_base.add(fn)
    if count > CAP:
        break

def matches(sig):
    if sig.endswith('/**'):                       # directory signal
        d = sig[:-3].strip('/').replace(os.sep, '/')
        if not d:
            return True
        base = d.split('/')[-1]
        if d in dirs_rel or base in dirs_base:
            return True
        return any(r == d or r.endswith('/' + d) for r in dirs_rel)
    pat = sig[3:] if sig.startswith('**/') else sig    # file signal
    if any(fnmatch.fnmatch(b, pat) for b in files_base):
        return True
    return any(fnmatch.fnmatch(r, sig) or fnmatch.fnmatch(r, pat) for r in files_rel)

out = [s for s in sigs if matches(s)]
if out:
    sys.stdout.write("\n".join(out) + "\n")
sys.exit(0)
PY
}

# plib_emit_json <shell_fn_name> — run a function that prints `key=value` lines and emit them as one JSON
# object (light bool/int coercion) for --json output. rc1 if the function name is unknown.
plib_emit_json() {
  local fn="${1:-}"; [ -n "$fn" ] || return 1
  command -v "$fn" >/dev/null 2>&1 || return 1
  _plib_py || return 1
  local _prog
  _prog="$(cat <<'PY'
import sys, json
def coerce(v):
    if v in ("true", "false"):
        return v == "true"
    s = v.lstrip("-")
    if s.isdigit():
        try:
            return int(v)
        except ValueError:
            return v
    return v
d = {}
for line in sys.stdin:
    line = line.rstrip("\n")
    if not line or "=" not in line:
        continue
    k, v = line.split("=", 1)
    d[k.strip()] = coerce(v)
print(json.dumps(d))
PY
)"
  "$fn" | python3 -c "$_prog"
}
