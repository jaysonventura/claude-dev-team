#!/usr/bin/env bash
# scripts/test-plugins.sh — self-contained test suite for the CDT plugin-bootstrap subsystem (v1.59.0).
#
# Runs entirely in a SANDBOX (a throwaway temp HOME) and MOCKS all external state: it never touches the
# real ~/.claude, never runs the real `claude` CLI, never hits the network, and never needs credentials.
# A PATH-shim named `claude` RECORDS its argv to a log and exits 0, so install/enable paths can be asserted
# by the exact command they *would* run — without mutating anything. Exits non-zero if any scenario fails.
#   Run locally:  bash scripts/test-plugins.sh
#
# ---------------------------------------------------------------------------------------------------------
# CONTRACT under test (the subsystem this suite pins — these are the interfaces the sibling hooks implement).
# The three hooks below may be built AFTER this suite (TDD-first). Until each exists, its scenarios report
# "BLOCKED (sibling not built)" and count as not-yet-passing; they go green once the hook meets the contract.
#
#   hooks/plugins-lib.sh   (sourced — frozen shell functions, fail-open; registry via $CDT_PLUGIN_REGISTRY)
#     plib_installed                 prints "id<TAB>version<TAB>scope" per INSTALLED plugin, resolving the
#                                    "<name>@<mkt>" keys of the version-2 map in
#                                    $HOME/.claude/plugins/installed_plugins.json against the registry.
#     plib_is_installed <id>         rc 0 if the registry <id> (bare, e.g. "superpowers") is installed, else rc 1
#     plib_is_enabled   <id>         rc 0 if <id> is enabled in settings.json "enabledPlugins", else rc 1
#     plib_has_marketplace <name>    rc 0 if marketplace <name> is a key in known_marketplaces.json, else rc 1
#     plib_probe_cli <bin> [bin...]  rc 0 if every named binary is on PATH, rc = #missing otherwise
#     plib_state_set <id> <state>    write a per-plugin override (enabled|disabled|manual|auto) into the
#     plib_state_get <id>            ~/.claude/.cdt/plugins-state.json overlay; get returns the overlay value
#                                    if set, else the registry default. The overlay is the source of truth
#                                    and survives a registry-file overwrite.
#     plib_redact                    stdin->stdout (also accepts one arg): masks secrets (GitHub PAT ghp_…)
#                                    so the raw secret body never appears in the output.
#     plib_detect_signals <dir>      prints each registry repoSignal glob matched under <dir>.
#
#   hooks/plugin-route.sh  (advisory plugin router — like cdt-route but for plugins; fail-open)
#     `plugin-route.sh "<task>"` reads repo signals from $PWD + task keywords from "$*"; prints matching
#     plugin ids (deferring any that conflict with a CDT agent). The Superpowers gate is $CDT_SUPERPOWERS_MODE
#     (read from the environment):
#       selective (default)  suggest superpowers only for high-complexity/risk tasks CDT does NOT own
#                            (planning/review/TDD/brainstorm are CDT-owned -> superpowers suppressed)
#       off                  never suggest superpowers
#       always               suggest superpowers for any non-CDT-owned task, marked [advisory]
#
#   hooks/plugins.sh       (`cdt-plugins` — inspect/manage companion plugins; delegates detection to plib)
#     install <id>          validate <id> against the registry, then `claude plugin install <id@mkt> -s <scope>`.
#                           CDT_PLUGIN_STRICT (default ON) gates only NON-official plugins: strict ON -> print
#                           remediation and do NOT invoke `claude`; CDT_PLUGIN_STRICT=0 -> shell out. Official
#                           plugins always shell out. A non-registry id is refused before any `claude` call.
#     enable|disable <id>   set the ~/.claude/.cdt overlay (plib_state_set) + `claude plugin enable|disable`.
# ---------------------------------------------------------------------------------------------------------
set -u

REPO="$(cd "$(dirname "$0")/.." && pwd)"
SBX="$(mktemp -d 2>/dev/null)" || { echo "test-plugins: cannot create sandbox"; exit 1; }
trap 'rm -rf "$SBX"' EXIT

# --- sandbox environment: everything the subsystem reads is redirected under the throwaway HOME ----------
export HOME="$SBX"
export CLAUDE_PLUGIN_ROOT="$REPO"
export CDT_PLUGIN_REGISTRY="$REPO/config/plugins.json"      # shipped read-only registry (plib honors this)
export CDT_ENV_FILE="$HOME/.claude/claude-dev-team.env"     # CDT config env (superpowers gate lives here)
export CDT_SETTINGS="$HOME/.claude/settings.json"
mkdir -p "$HOME/.claude/plugins" "$HOME/.claude/.cdt" "$HOME/.claude/bin" "$SBX/bin"
touch "$HOME/.claude/.cdt-menubar-disabled"                 # never build the macOS menu bar in a test
: > "$CDT_ENV_FILE"

# --- `claude` PATH-shim: records argv, returns a plausible version, NEVER mutates the real environment ---
SHIM_LOG="$SBX/claude-argv.log"; : > "$SHIM_LOG"
cat > "$SBX/bin/claude" <<SHIM
#!/usr/bin/env bash
# CDT test shim — records argv to the log, never installs anything, never calls the real claude CLI.
printf '%s\n' "\$*" >> "$SHIM_LOG"
case "\${1:-}" in --version|-v|version) echo "2.1.207 (Claude Code cdt-test-shim)";; esac
exit 0
SHIM
chmod +x "$SBX/bin/claude"
export PATH="$SBX/bin:$PATH"

# --- fixtures: fake plugin state (version-2 installed map, marketplaces, enabledPlugins) -----------------
cat > "$HOME/.claude/plugins/installed_plugins.json" <<'JSON'
{
  "version": 2,
  "plugins": {
    "superpowers@claude-plugins-official":    [ { "scope": "user", "installPath": "/x/superpowers/1.0.0",    "version": "1.0.0" } ],
    "code-review@claude-plugins-official":     [ { "scope": "user", "installPath": "/x/code-review/1.0.0",     "version": "1.0.0" } ],
    "frontend-design@claude-plugins-official": [ { "scope": "user", "installPath": "/x/frontend-design/1.0.0", "version": "1.0.0" } ],
    "context7@claude-plugins-official":        [ { "scope": "user", "installPath": "/x/context7/1.0.0",        "version": "1.0.0" } ]
  }
}
JSON

cat > "$HOME/.claude/plugins/known_marketplaces.json" <<'JSON'
{
  "claude-plugins-official": {
    "source": { "source": "github", "repo": "anthropics/claude-plugins-official" },
    "installLocation": "/x/marketplaces/claude-plugins-official",
    "lastUpdated": "2026-07-12T00:00:00.000Z"
  }
}
JSON

# enabledPlugins seeded in BOTH plugin-scoped and top-level settings so plib_is_enabled finds it either place.
ENABLED='{ "enabledPlugins": { "superpowers@claude-plugins-official": true, "code-review@claude-plugins-official": true, "frontend-design@claude-plugins-official": true, "context7@claude-plugins-official": true } }'
printf '%s\n' "$ENABLED" > "$HOME/.claude/plugins/settings.json"
printf '%s\n' "$ENABLED" > "$HOME/.claude/settings.json"

# --- fixture projects with repo signal files ------------------------------------------------------------
mkdir -p "$SBX/proj-react/src" "$SBX/proj-laravel/app/Http" "$SBX/proj-tf" "$SBX/proj-swift" "$SBX/proj-empty"
printf '{ "name":"app","dependencies":{"react":"^18","react-dom":"^18"},"devDependencies":{"vite":"^5"} }\n' > "$SBX/proj-react/package.json"
printf '{}\n' > "$SBX/proj-react/tsconfig.json"
printf 'export default function App(){ return null }\n' > "$SBX/proj-react/src/App.tsx"
printf '{ "require": { "laravel/framework": "^11" } }\n' > "$SBX/proj-laravel/composer.json"
printf '#!/usr/bin/env php\n<?php\n' > "$SBX/proj-laravel/artisan"
printf '<?php\n' > "$SBX/proj-laravel/app/Http/Controller.php"
printf 'resource "null_resource" "x" {}\n' > "$SBX/proj-tf/main.tf"
printf '// swift-tools-version:5.9\nimport PackageDescription\n' > "$SBX/proj-swift/Package.swift"

# --- counters + assertion helpers -----------------------------------------------------------------------
PASS=0; BLOCKED=0
pass()    { PASS=$((PASS+1)); printf '  ok   [%2s] %s\n' "$1" "$2"; }
fail()    { printf '  FAIL [%2s] %s\n' "$1" "$2"; [ -n "${3:-}" ] && printf '           %s\n' "$3"; return 0; }
blocked() { BLOCKED=$((BLOCKED+1)); printf '  FAIL [%2s] %s\n           BLOCKED (sibling not built): %s\n' "$1" "$2" "$3"; return 0; }
want()    { case "$3" in *"$4"*) pass "$1" "$2";; *) fail "$1" "$2" "wanted \"$4\" — got: $(printf '%s' "$3" | tr '\n' ' ' | cut -c1-160)";; esac; }
lack()    { case "$3" in *"$4"*) fail "$1" "$2" "did NOT want \"$4\" — got: $(printf '%s' "$3" | tr '\n' ' ' | cut -c1-160)";; *) pass "$1" "$2";; esac; }
has_fn()  { [ "$(type -t "$1" 2>/dev/null)" = function ]; }
need_fn() { if has_fn "$3"; then return 0; fi; blocked "$1" "$2" "hooks/plugins-lib.sh:$3() not defined"; return 1; }
need_file(){ if [ -f "$1" ]; then return 0; fi; blocked "$2" "$3" "$(basename "$1") not built yet"; return 1; }

LIB="$REPO/hooks/plugins-lib.sh"; PSH="$REPO/hooks/plugins.sh"; PRT="$REPO/hooks/plugin-route.sh"
# shellcheck disable=SC1090
[ -f "$LIB" ] && . "$LIB" 2>/dev/null

route() {  # route <projdir> <task words...> — plugin-route reads repo signals from $PWD + task keywords
  local d="$1"; shift
  ( cd "$d" 2>/dev/null && bash "$PRT" "$*" 2>/dev/null )
}
set_gate() { export CDT_SUPERPOWERS_MODE="$1"; }   # plugin-route reads the gate from the environment

echo "== Registry (config/plugins.json) =="
# (1) registry parses to a non-empty plugins array
if REG="$CDT_PLUGIN_REGISTRY" python3 - <<'PY' 2>/dev/null
import json,os,sys
d=json.load(open(os.environ["REG"]))
sys.exit(0 if isinstance(d.get("plugins"),list) and d["plugins"] else 1)
PY
then pass 1 "config/plugins.json parses to a non-empty plugins[]"; else fail 1 "config/plugins.json parses"; fi

# (2) every row carries all required keys; ids are unique
if REG="$CDT_PLUGIN_REGISTRY" python3 - <<'PY' 2>/dev/null
import json,os,sys
REQ={"id","displayName","type","marketplace","installIdentifier","enabledByDefault","required","scope",
     "categories","dependencies","activationRules","conflicts","needsAuth","securityLevel","fallbackBehavior"}
d=json.load(open(os.environ["REG"])); rows=d["plugins"]; ids=[]
for p in rows:
    miss=REQ-set(p)
    if miss: print("missing",p.get("id"),sorted(miss)); sys.exit(1)
    ids.append(p["id"])
sys.exit(0 if len(ids)==len(set(ids)) else 1)
PY
then pass 2 "every row has all 15 required keys + ids unique"; else fail 2 "required keys / unique ids"; fi

# (3) non-cdt-skill installIdentifier matches ^id@marketplace$; cdt-skill rows have null
if REG="$CDT_PLUGIN_REGISTRY" python3 - <<'PY' 2>/dev/null
import json,os,re,sys
rx=re.compile(r'^[A-Za-z0-9._-]+@[A-Za-z0-9._-]+$')
d=json.load(open(os.environ["REG"]))
for p in d["plugins"]:
    if p.get("type")=="cdt-skill":
        if p.get("installIdentifier") is not None: print("cdt-skill not null",p.get("id")); sys.exit(1)
    else:
        ii=p.get("installIdentifier")
        if not (isinstance(ii,str) and rx.match(ii)): print("bad installIdentifier",p.get("id"),ii); sys.exit(1)
sys.exit(0)
PY
then pass 3 "installIdentifier regex holds; cdt-skill rows null"; else fail 3 "installIdentifier regex / null"; fi

# (4) ui-ux-pro-max is a local cdt-skill with no install identifier
if REG="$CDT_PLUGIN_REGISTRY" python3 - <<'PY' 2>/dev/null
import json,os,sys
d=json.load(open(os.environ["REG"]))
r=[p for p in d["plugins"] if p.get("id")=="ui-ux-pro-max"]
sys.exit(0 if r and r[0].get("type")=="cdt-skill" and r[0].get("installIdentifier") is None else 1)
PY
then pass 4 "ui-ux-pro-max type==cdt-skill, no install"; else fail 4 "ui-ux-pro-max cdt-skill/no-install"; fi

echo "== Detection (plugins-lib.sh) =="
# (5) plib_installed parses the version-2 map
if need_fn 5 "plib_installed parses the version:2 map" plib_installed; then
  want 5 "plib_installed parses the version:2 map" "$(plib_installed 2>/dev/null)" "superpowers"
fi
# (6) plib_is_installed hit + miss
if need_fn 6 "plib_is_installed hit+miss" plib_is_installed; then
  plib_is_installed superpowers >/dev/null 2>&1; hit=$?
  plib_is_installed cdt-not-a-real-plugin >/dev/null 2>&1; miss=$?
  if [ "$hit" -eq 0 ] && [ "$miss" -ne 0 ]; then pass 6 "plib_is_installed hit+miss"
  else fail 6 "plib_is_installed hit+miss" "hit rc=$hit (want 0) · miss rc=$miss (want non-zero)"; fi
fi
# (7) plib_is_enabled reads settings enabledPlugins
if need_fn 7 "plib_is_enabled reads enabledPlugins" plib_is_enabled; then
  plib_is_enabled superpowers >/dev/null 2>&1; en=$?
  plib_is_enabled github >/dev/null 2>&1; dis=$?
  if [ "$en" -eq 0 ] && [ "$dis" -ne 0 ]; then pass 7 "plib_is_enabled enabled+disabled"
  else fail 7 "plib_is_enabled enabled+disabled" "enabled rc=$en (want 0) · disabled rc=$dis (want non-zero)"; fi
fi
# (8) marketplace present + absent
if need_fn 8 "plib_has_marketplace present+absent" plib_has_marketplace; then
  plib_has_marketplace claude-plugins-official >/dev/null 2>&1; mp=$?
  plib_has_marketplace cdt-no-such-market >/dev/null 2>&1; ma=$?
  if [ "$mp" -eq 0 ] && [ "$ma" -ne 0 ]; then pass 8 "marketplace present+absent"
  else fail 8 "marketplace present+absent" "present rc=$mp (want 0) · absent rc=$ma (want non-zero)"; fi
fi
# (9) plib_probe_cli all-present
if need_fn 9 "plib_probe_cli all-present" plib_probe_cli; then
  plib_probe_cli sh >/dev/null 2>&1; r=$?
  if [ "$r" -eq 0 ]; then pass 9 "plib_probe_cli all-present -> rc0"; else fail 9 "plib_probe_cli all-present" "rc=$r (want 0)"; fi
fi
# (10) plib_probe_cli missing-binary -> rc1
if need_fn 10 "plib_probe_cli missing-binary -> rc1" plib_probe_cli; then
  plib_probe_cli sh cdt-nonexistent-binary-xyz >/dev/null 2>&1; r=$?
  if [ "$r" -ne 0 ]; then pass 10 "plib_probe_cli missing-binary -> rc non-zero"; else fail 10 "plib_probe_cli missing-binary" "rc=$r (want non-zero)"; fi
fi

echo "== Routing (plugin-route.sh) =="
if need_file "$PRT" 11 "react/vite -> frontend-design(+typescript-lsp)"; then
  out="$(route "$SBX/proj-react" work on this project)"
  case "$out" in *frontend-design*typescript-lsp*|*typescript-lsp*frontend-design*) pass 11 "react/vite -> frontend-design + typescript-lsp";;
    *) if printf '%s' "$out" | grep -q frontend-design && printf '%s' "$out" | grep -q typescript-lsp; then pass 11 "react/vite -> frontend-design + typescript-lsp"
       else fail 11 "react/vite -> frontend-design + typescript-lsp" "got: $(printf '%s' "$out" | tr '\n' ' ' | cut -c1-160)"; fi;; esac
fi
[ -f "$PRT" ] && { out="$(route "$SBX/proj-laravel" work on this project)"
  if printf '%s' "$out" | grep -q laravel-boost && printf '%s' "$out" | grep -q php-lsp; then pass 12 "composer+artisan -> laravel-boost + php-lsp"
  else fail 12 "composer+artisan -> laravel-boost + php-lsp" "got: $(printf '%s' "$out" | tr '\n' ' ' | cut -c1-160)"; fi; } || blocked 12 "composer+artisan -> laravel-boost(+php-lsp)" "plugin-route.sh not built yet"
[ -f "$PRT" ] && want 13 "*.tf -> terraform" "$(route "$SBX/proj-tf" work on this project)" "terraform" || blocked 13 "*.tf -> terraform" "plugin-route.sh not built yet"
[ -f "$PRT" ] && want 14 "Package.swift -> swift-lsp" "$(route "$SBX/proj-swift" work on this project)" "swift-lsp" || blocked 14 "Package.swift -> swift-lsp" "plugin-route.sh not built yet"
[ -f "$PRT" ] && want 15 "crash kw -> sentry" "$(route "$SBX/proj-empty" the app crash produced a stacktrace exception)" "sentry" || blocked 15 "crash kw -> sentry" "plugin-route.sh not built yet"
[ -f "$PRT" ] && want 16 "PR kw -> github" "$(route "$SBX/proj-empty" please open a pull request on github)" "github" || blocked 16 "PR kw -> github" "plugin-route.sh not built yet"
[ -f "$PRT" ] && want 17 "lib-version kw -> context7" "$(route "$SBX/proj-empty" check the library version in the docs api)" "context7" || blocked 17 "lib-version kw -> context7" "plugin-route.sh not built yet"
[ -f "$PRT" ] && want 18 "e2e kw -> playwright" "$(route "$SBX/proj-empty" write an e2e end-to-end browser test with playwright)" "playwright" || blocked 18 "e2e kw -> playwright" "plugin-route.sh not built yet"

echo "== Superpowers gate (plugin-route.sh — CDT_SUPERPOWERS_MODE) =="
# (19) selective: a planning/review task is CDT-owned -> superpowers is suppressed
if need_file "$PRT" 19 "selective suppresses planning/review superpowers"; then
  set_gate selective
  lack 19 "selective suppresses planning/review superpowers" "$(route "$SBX/proj-empty" plan and review the architecture)" "superpowers"
fi
# (20) off: even a high-complexity task that WOULD surface superpowers under selective gets nothing
if [ -f "$PRT" ]; then
  set_gate off
  lack 20 "off -> no superpowers suggestion" "$(route "$SBX/proj-empty" optimize a distributed algorithm for concurrency)" "superpowers"
else blocked 20 "off -> no superpowers suggestion" "plugin-route.sh not built yet"; fi
# (21) always: a neutral (non-CDT-owned) task surfaces superpowers, marked advisory/downgraded
if [ -f "$PRT" ]; then
  set_gate always
  out="$(route "$SBX/proj-empty" scaffold a small helper module)"
  low="$(printf '%s' "$out" | tr 'A-Z' 'a-z')"
  if printf '%s' "$out" | grep -q superpowers && printf '%s' "$low" | grep -q advisory; then pass 21 "always -> superpowers present, advisory/downgraded"
  else fail 21 "always -> superpowers advisory" "got: $(printf '%s' "$out" | tr '\n' ' ' | cut -c1-160)"; fi
else blocked 21 "always -> superpowers advisory/downgraded" "plugin-route.sh not built yet"; fi
unset CDT_SUPERPOWERS_MODE   # clear the gate before the CLI tests

echo "== CLI + safety (plugins.sh — CDT_PLUGIN_STRICT / CDT_PLUGIN_AUTO_INSTALL) =="
# (22) strict ON blocks a THIRD-PARTY auto-install: prints remediation, `claude` shim NOT invoked.
#      (github is verified-third-party; strict gates only non-official plugins.)
if need_file "$PSH" 22 "strict=1 blocks a third-party install (shim not invoked)"; then
  : > "$SHIM_LOG"
  out="$(CDT_PLUGIN_STRICT=1 CDT_PLUGIN_AUTO_INSTALL=1 bash "$PSH" install github 2>&1)"
  if [ ! -s "$SHIM_LOG" ] && [ -n "$out" ]; then pass 22 "strict=1 blocks a third-party install (shim not invoked, remediation printed)"
  else fail 22 "strict=1 blocks a third-party install" "shim-log-bytes=$(wc -c <"$SHIM_LOG" | tr -d ' ') · out=$(printf '%s' "$out" | tr '\n' ' ' | cut -c1-120)"; fi
fi
# (23) strict=0 install shells out with `install <id@mkt> -s <scope>`
if need_file "$PSH" 23 "install shells out with install <id@mkt> -s <scope>"; then
  : > "$SHIM_LOG"
  CDT_PLUGIN_AUTO_INSTALL=1 CDT_PLUGIN_STRICT=0 bash "$PSH" install github >/dev/null 2>&1
  if grep -q 'install github@claude-plugins-official -s user' "$SHIM_LOG"; then pass 23 "install shells out: install github@claude-plugins-official -s user"
  else fail 23 "install shells out (id@mkt + scope)" "shim-log: $(tr '\n' '|' <"$SHIM_LOG" | cut -c1-160)"; fi
fi
# (24) install of a non-registry id is refused before any `claude` call (shim NOT invoked)
if need_file "$PSH" 24 "non-registry install is refused (shim not invoked)"; then
  : > "$SHIM_LOG"
  out="$(CDT_PLUGIN_AUTO_INSTALL=1 CDT_PLUGIN_STRICT=0 bash "$PSH" install cdt-bogus-not-in-registry 2>&1)"; rc=$?
  low="$(printf '%s' "$out" | tr 'A-Z' 'a-z')"
  if [ ! -s "$SHIM_LOG" ] && { [ "$rc" -ne 0 ] || printf '%s' "$low" | grep -Eq 'not in|refus|unknown|reject|registry'; }; then
    pass 24 "non-registry install refused (shim not invoked)"
  else fail 24 "non-registry install refused" "rc=$rc · shim-bytes=$(wc -c <"$SHIM_LOG" | tr -d ' ') · out=$(printf '%s' "$out" | tr '\n' ' ' | cut -c1-120)"; fi
fi
# (25) overlay enable/disable survives a registry-file overwrite. The `cdt-plugins enable|disable` CLI
#      verbs write the ~/.cdt overlay via plib_state_set; the overlay is the source of truth and overrides
#      the registry defaults even after the registry file is rewritten.
if need_file "$PSH" 25 "overlay enable/disable survives a registry overwrite"; then
  REGCOPY="$SBX/registry-copy.json"; cp "$REPO/config/plugins.json" "$REGCOPY"
  OVL="$HOME/.claude/.cdt/plugins-state.json"
  CDT_PLUGIN_REGISTRY="$REGCOPY" CDT_PLUGIN_STRICT=0 bash "$PSH" disable superpowers >/dev/null 2>&1  # default: auto
  CDT_PLUGIN_REGISTRY="$REGCOPY" CDT_PLUGIN_STRICT=0 bash "$PSH" enable  github      >/dev/null 2>&1  # default: disabled
  cp "$REPO/config/plugins.json" "$REGCOPY"                                                           # overwrite the registry file
  sp="$(CDT_PLUGIN_REGISTRY="$REGCOPY" plib_state_get superpowers 2>/dev/null)"
  gh="$(CDT_PLUGIN_REGISTRY="$REGCOPY" plib_state_get github     2>/dev/null)"
  if [ -f "$OVL" ] && [ "$sp" = disabled ] && [ "$gh" = enabled ]; then
    pass 25 "overlay persists across a registry overwrite (superpowers=disabled, github=enabled — overrides registry defaults)"
  else fail 25 "overlay persists across registry overwrite" "state: superpowers=$sp (want disabled) · github=$gh (want enabled)"; fi
fi
# (26) plib_redact masks a fake GitHub PAT in captured output
if need_fn 26 "plib_redact masks a fake PAT" plib_redact; then
  SECRET="ghp_A1b2C3d4E5f6G7h8I9j0KLMNOPqrstuv12"
  red="$(printf 'authorization: token %s trailing\n' "$SECRET" | plib_redact 2>/dev/null)"
  [ -z "$red" ] && red="$(plib_redact "authorization: token $SECRET trailing" 2>/dev/null)"
  if [ -n "$red" ]; then lack 26 "plib_redact masks the PAT (raw secret absent)" "$red" "$SECRET"
  else fail 26 "plib_redact masks a fake PAT" "plib_redact produced no output"; fi
fi

echo "== Env-file config (plib_cfg reads claude-dev-team.env, not just process env) =="
# (27) CDT_PLUGINS_ENABLED=0 written to the persisted env file — with the var UNSET in the environment —
#      silences the advisory router. Proves the config knobs take effect from the file, not just $ENV.
if need_file "$PRT" 27 "env-file CDT_PLUGINS_ENABLED=0 silences the router"; then
  printf 'CDT_PLUGINS_ENABLED=0\n' > "$CDT_ENV_FILE"
  out="$( unset CDT_PLUGINS_ENABLED; cd "$SBX/proj-react" 2>/dev/null && bash "$PRT" "build a react ui" 2>/dev/null )"
  : > "$CDT_ENV_FILE"   # restore the empty env file
  if [ -z "$out" ]; then pass 27 "env-file CDT_PLUGINS_ENABLED=0 -> router silent (var unset; read from the env file)"
  else fail 27 "env-file CDT_PLUGINS_ENABLED=0 -> router silent" "got: $(printf '%s' "$out" | tr '\n' ' ' | cut -c1-160)"; fi
fi

echo "== Overlay gating + community tier (plugin-route.sh) =="
# Hermetic: point CDT_HOME at a sandbox so these never read or write the real ~/.claude/.cdt overlay.
OVL_HOME="$SBX/ovl-home"; mkdir -p "$OVL_HOME/.cdt" 2>/dev/null
set_overlay() { printf '%s\n' "$1" > "$OVL_HOME/.cdt/plugins-state.json"; }
route_ovl() {  # route_ovl <projdir> <task words...> — same as route(), with the sandboxed overlay in effect
  local d="$1"; shift
  ( cd "$d" 2>/dev/null && CDT_HOME="$OVL_HOME" bash "$PRT" "$*" 2>/dev/null )
}

# (28) REGRESSION: plib_state_set writes PLAIN STRINGS, so a `"terraform":"disabled"` overlay must suppress
#      the recommendation. Before the string branch existed, _mark() only understood dicts/bool-false and a
#      disabled plugin was still recommended — contradicting the documented "never recommends a plugin
#      whose overlay is disabled".
if need_file "$PRT" 28 "string overlay 'disabled' suppresses a recommendation"; then
  set_overlay '{ "terraform": "disabled" }'
  lack 28 "overlay terraform=disabled -> terraform NOT recommended" "$(route_ovl "$SBX/proj-tf" work on this project)" "terraform"
fi

# (29) A community-third-party row stays completely silent until explicitly enabled, so the shipped
#      defaults never mention a plugin the user has not opted into.
if need_file "$PRT" 29 "community row silent without an explicit opt-in"; then
  set_overlay '{}'
  lack 29 "no overlay -> ponytail absent entirely" "$(route_ovl "$SBX/proj-react" simplify this over-engineered module)" "ponytail"
fi

# (30) Once opted in, the community row is matched only to DEFER — CDT owns the lane, so it must appear as
#      deferred and never as a recommendation.
if need_file "$PRT" 30 "opted-in community row defers to CDT"; then
  set_overlay '{ "ponytail": "enabled" }'
  out="$(route_ovl "$SBX/proj-react" simplify this over-engineered module)"
  want 30 "overlay ponytail=enabled -> ponytail deferred (CDT owns simplify)" "$out" "ponytail"
  case "$out" in *deferred*) : ;; *) fail 30 "ponytail must be DEFERRED, not recommended" "got: $(printf '%s' "$out" | tr '\n' ' ' | cut -c1-160)";; esac
fi

echo
echo "PASSED $PASS/30"
[ "$BLOCKED" -gt 0 ] && echo "($BLOCKED scenario(s) BLOCKED on sibling hooks not yet built — see BLOCKED lines above)"
if [ "$PASS" -eq 30 ]; then echo "ALL PLUGIN TESTS PASSED"; exit 0; else echo "PLUGIN TESTS INCOMPLETE OR FAILING"; exit 1; fi
