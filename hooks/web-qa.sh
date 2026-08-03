#!/usr/bin/env bash
# cdt-web-qa — the browser control plane for autonomous WEB QA.
#
# The web twin of cdt-mobile-qa. One thin wrapper per capability an agent needs to drive a real
# browser through Playwright, plus a `doctor` gate and `scaffold` for the shipped harness. Artifacts
# are UNIFIED with mobile — <repo>/.claude/qa/web/<runid> sits next to .claude/qa/mobile/<runid> — and
# every path printed on stdout is ABSOLUTE so an agent can parse and cite it. Honest by construction:
# if playwright, or a browser engine, is missing, the subcommand fails loudly with a fix hint and a
# non-zero exit. It NEVER prints a success line for something that did not happen; that is the whole
# point of this feature.
#
# Nothing here installs anything implicitly. `browsers --install` is the single exception, and only
# when you ask for it by name.
set +e

PROG="cdt-web-qa"
SELF_DIR="$(cd "$(dirname "$0")" 2>/dev/null && pwd)"
CDT_HOME="${CDT_HOME:-$HOME/.claude}"

die()  { echo "$PROG: $*" >&2; exit 1; }
note() { echo "$PROG: $*"; }

# Install hint for the detected package manager — same style as deps.sh.
node_hint() {
  if   command -v brew    >/dev/null 2>&1; then echo "brew install node"
  elif command -v apt-get >/dev/null 2>&1; then echo "sudo apt-get install -y nodejs npm"
  elif command -v dnf     >/dev/null 2>&1; then echo "sudo dnf install -y nodejs"
  elif command -v pacman  >/dev/null 2>&1; then echo "sudo pacman -S --noconfirm nodejs npm"
  elif command -v winget  >/dev/null 2>&1; then echo "winget install -e --id OpenJS.NodeJS.LTS"
  else echo "get Node 18+ from https://nodejs.org"
  fi
}

# Names that become file/dir components (or a module id the harness imports). Blocks path traversal
# and option injection (same posture as cdt-mobile-qa's safe_name).
safe_name() {
  case "$1" in
    ''|-*|*..*|*/*|*[!A-Za-z0-9._-]*)
      die "invalid name '$1' — use letters, digits, '.', '_', '-' (no '/', no '..')." ;;
  esac
}

# `playwright` on PATH, else an already-installed copy resolvable from the CURRENT directory.
# --no-install is load-bearing: a plain `npx playwright` would DOWNLOAD the package (or hang on its
# prompt when non-interactive), and this tool installs nothing the user did not ask for. npx resolves
# out of ./node_modules, so a caller that needs the harness's own copy must cd into it FIRST.
pw_cmd() {
  if command -v playwright >/dev/null 2>&1; then echo "playwright"
  elif command -v npx >/dev/null 2>&1 && npx --no-install playwright --version >/dev/null 2>&1; then echo "npx --no-install playwright"
  fi
}

# Where playwright unpacks its engines. This is what we can actually VERIFY: `install --dry-run`
# prints the paths it WOULD use whether or not anything is there, so it cannot answer "is it
# installed?". A completed engine dir carries an INSTALLATION_COMPLETE marker; a half-downloaded or
# interrupted one does not, so the marker — not the directory — is the test.
browsers_root() {
  local d
  # PLAYWRIGHT_BROWSERS_PATH=0 means "engines live inside node_modules", which this check cannot see.
  # Report "unknown" rather than probing a bogus path — claiming FAIL there would be a lie.
  [ "${PLAYWRIGHT_BROWSERS_PATH:-}" = "0" ] && return 1
  if [ -n "${PLAYWRIGHT_BROWSERS_PATH:-}" ]; then echo "$PLAYWRIGHT_BROWSERS_PATH"; return 0; fi
  for d in "$HOME/Library/Caches/ms-playwright" "$HOME/.cache/ms-playwright" "${LOCALAPPDATA:-}/ms-playwright"; do
    [ -d "$d" ] && { echo "$d"; return 0; }
  done
  return 1
}

# $1 = chromium|firefox|webkit, $2 = browsers root. The '-*' glob is version-suffixed and does NOT
# match chromium_headless_shell-*, which is a different package.
engine_installed() {
  [ -n "$2" ] || return 1
  ls -d "$2/$1"-*/INSTALLATION_COMPLETE >/dev/null 2>&1
}

# One run = one dir, so a multi-command scenario keeps its artifacts together: reuse the newest
# existing run, start a fresh one with `artifacts --clean` or by exporting CDT_QA_RUNID. Same
# semantics (and the same env vars) as the mobile side — that is what makes the layout unified.
artifacts_dir() {
  local root dir run
  if [ -n "${CDT_QA_ARTIFACTS:-}" ]; then
    dir="$CDT_QA_ARTIFACTS"
  else
    root="$(git rev-parse --show-toplevel 2>/dev/null)"; [ -n "$root" ] || root="$PWD"
    root="$root/.claude/qa/web"
    if [ -n "${CDT_QA_RUNID:-}" ]; then
      run="$CDT_QA_RUNID"; safe_name "$run"
    else
      # shellcheck disable=SC2012  # run ids are timestamps we create; -t ordering is the point
      run="$(ls -t "$root" 2>/dev/null | head -1)"
      [ -n "$run" ] && [ -d "$root/$run" ] || run="$(date +%Y%m%d-%H%M%S)"
    fi
    dir="$root/$run"
  fi
  local fresh=0
  [ -d "$dir" ] || fresh=1
  mkdir -p "$dir" 2>/dev/null || die "cannot create artifacts dir: $dir"
  # Self-ignoring: captures are screenshots, video and traces — a Playwright trace replays the whole
  # session including typed passwords and Authorization headers, so they must never be committable.
  # A repo-level .gitignore cannot cover a custom CDT_QA_ARTIFACTS pointing elsewhere, so the
  # artifacts root ignores itself (including this file). ONLY for a dir we just created, or one that
  # is empty. Writing '*' into a pre-existing directory would silently hide whatever already lives
  # there — if CDT_QA_ARTIFACTS points at real source, that erases it from `git status`. Never change
  # what git tracks in a directory we do not own.
  if [ ! -f "$dir/.gitignore" ]; then
    if [ "$fresh" = 1 ] || [ -z "$(ls -A "$dir" 2>/dev/null)" ]; then
      printf '*\n' > "$dir/.gitignore" 2>/dev/null
    else
      # Say so rather than skipping silently — the user's custom root is NOT protected, and captures
      # written here can be committed.
      echo "$PROG: NOTE: '$dir' already has content, so no .gitignore was written — captures here are" >&2
      echo "$PROG:       NOT protected from commit. Add '*' to $dir/.gitignore yourself." >&2
    fi
  fi
  # -P resolves symlinks: the --clean containment check compares these strings, and a logical path
  # would let a symlinked artifacts root alias past it and delete the link target.
  (cd "$dir" 2>/dev/null && pwd -P) || die "cannot resolve artifacts dir: $dir"
}

# ---------------------------------------------------------------- doctor ----
DOC_BAD=0
P() { echo "  [PASS] $1"; }
W() { echo "  [WARN] $1 — $2"; }
F() { echo "  [FAIL] $1 — $2"; DOC_BAD=$((DOC_BAD+1)); }

cmd_doctor() {
  local pw root e n=0
  echo "$PROG — doctor  (cwd: $PWD)"

  if command -v node >/dev/null 2>&1; then P "node $(node --version 2>/dev/null)"
  else F "node not found" "playwright is a Node tool — install Node 18+: $(node_hint)"; fi

  pw="$(pw_cmd)"
  if [ -n "$pw" ]; then
    # shellcheck disable=SC2086
    P "playwright $($pw --version 2>/dev/null | tail -1) (via '$pw')"
  else
    F "playwright not resolvable from $PWD" "npx resolves out of ./node_modules — run doctor inside the harness ($PROG scaffold, then npm install), or: npm i -D @playwright/test"
  fi

  # Engine check, stated with its method so the result is auditable rather than asserted.
  root="$(browsers_root)"
  if [ -z "$root" ]; then
    if [ "${PLAYWRIGHT_BROWSERS_PATH:-}" = "0" ]; then
      # Engines live inside node_modules by explicit configuration — genuinely unverifiable here, and
      # a FAIL would be a lie. WARN and say how to check.
      W "engines live in node_modules (PLAYWRIGHT_BROWSERS_PATH=0) — cannot verify from here" "check with: $pw install --dry-run"
    else
      # No cache directory at ALL means no engine has ever been unpacked. That is the first-run state
      # this tool's own last line creates, and it must not read as ready: a WARN here exited 0 while
      # zero browsers existed, so `doctor` blessed a machine that cannot run a single test.
      F "no browser engine installed (no playwright cache at ~/Library/Caches/ms-playwright or ~/.cache/ms-playwright)" "run: $PROG browsers --install"
    fi
  else
    echo "  engines checked in $root (INSTALLATION_COMPLETE marker per engine dir)"
    for e in chromium firefox webkit; do
      if engine_installed "$e" "$root"; then P "$e installed"; n=$((n+1))
      else W "$e not installed" "run: $PROG browsers --install (installs all three)"; fi
    done
    [ "$n" -gt 0 ] || F "no browser engine installed" "run: $PROG browsers --install"
  fi

  if command -v claude >/dev/null 2>&1; then
    if claude mcp list 2>/dev/null | grep -qi playwright; then P "Playwright MCP server wired"
    else W "no Playwright MCP server wired" "CDT ships it as a plugin dependency, so this is unusual — check 'claude plugin list', or add it: claude mcp add"; fi
  else
    W "claude CLI not on PATH" "cannot check MCP wiring (optional — $PROG drives the playwright CLI directly)"
  fi

  echo
  [ "$DOC_BAD" -eq 0 ] && { note "ready — no FAIL lines."; exit 0; }
  note "$DOC_BAD check(s) FAILED — browser work will not run until they are fixed."
  exit 1
}

# -------------------------------------------------------------- browsers ----
cmd_browsers() {
  local install=0 a pw root e n=0
  for a in "$@"; do case "$a" in --install) install=1 ;; *) die "unknown flag: $a" ;; esac; done
  if [ "$install" = 1 ]; then
    pw="$(pw_cmd)"
    [ -n "$pw" ] || die "playwright not resolvable from $PWD — run this inside the harness, or: npm i -D @playwright/test"
    note "downloading browser engines (hundreds of MB) via '$pw install'"
    # shellcheck disable=SC2086
    $pw install || die "playwright install failed — nothing was installed"
  fi
  root="$(browsers_root)"
  [ -n "$root" ] || die "cannot locate playwright's browser cache (PLAYWRIGHT_BROWSERS_PATH=${PLAYWRIGHT_BROWSERS_PATH:-unset}) — cannot verify what is installed"
  echo "browsers root: $root"
  for e in chromium firefox webkit; do
    if engine_installed "$e" "$root"; then echo "  [installed] $e"; n=$((n+1))
    else echo "  [missing]   $e"; fi
  done
  [ "$n" -gt 0 ] || note "no engine installed — run: $PROG browsers --install"
}

# ------------------------------------------------------------- artifacts ----
cmd_artifacts() {
  local clean=0 a dir root
  for a in "$@"; do case "$a" in --dir) : ;; --clean) clean=1 ;; *) die "unknown flag: $a" ;; esac; done
  # Validate BEFORE acquiring. artifacts_dir() creates the directory (and writes a self-ignoring
  # .gitignore into it), so resolving first meant a REFUSED --clean still created and littered the
  # very path it was about to refuse to delete.
  if [ "$clean" = 1 ] && [ -n "${CDT_QA_ARTIFACTS:-}" ] && [ ! -d "$CDT_QA_ARTIFACTS" ]; then
    die "nothing to clean — '$CDT_QA_ARTIFACTS' does not exist (refusing to create it just to delete it)."
  fi
  dir="$(artifacts_dir)" || exit 1
  if [ "$clean" = 1 ]; then
    # Containment, not a substring match. A `*/qa/*` pattern matches ANY path with a qa segment, so
    # `CDT_QA_ARTIFACTS=<proj>/qa/src artifacts --clean` would rm -rf real source. Only a run dir
    # DIRECTLY under this repo's own artifacts root may be deleted, compared as physical paths.
    root="$(git rev-parse --show-toplevel 2>/dev/null)"; [ -n "$root" ] || root="$PWD"
    root="$root/.claude/qa/web"
    [ -d "$root" ] && root="$(cd "$root" && pwd -P)"
    case "$dir" in
      "$root"|"$root"/*) ;;
      *) die "refusing to delete '$dir' — it is not inside this repo's artifacts root ($root)." ;;
    esac
    # A run dir is one level down; never let a deeper or aliased path through.
    [ "$(dirname "$dir")" = "$root" ] || [ "$dir" = "$root" ] \
      || die "refusing to delete '$dir' — only '$root' or a run dir directly inside it."
    rm -rf "$dir" && note "removed $dir"
    return 0
  fi
  echo "$dir"
}

# ------------------------------------------------------------------ test ----
cmd_test() {
  local app="" br="" dir="" adir pw c
  while [ $# -gt 0 ]; do
    case "$1" in
      --app)     app="${2:-}"; [ -n "$app" ] || die "--app needs an id"; safe_name "$app"; shift 2 ;;
      --browser) br="${2:-}"
                 case "$br" in chromium|firefox|webkit) ;;
                   *) die "--browser must be chromium, firefox or webkit (got '${br:-}')" ;;
                 esac; shift 2 ;;
      --) shift; break ;;
      *) die "unknown flag: $1 — playwright's own args go after '--' (e.g. $PROG test -- --headed)" ;;
    esac
  done
  for c in "${CDT_WQA_DIR:-}" "$PWD/qa-web" "$PWD"; do
    [ -n "$c" ] && ls "$c"/playwright.config.* >/dev/null 2>&1 && { dir="$c"; break; }
  done
  [ -n "$dir" ] || die "no harness found (looked in ${CDT_WQA_DIR:+$CDT_WQA_DIR, }$PWD/qa-web and $PWD)
       — create one with: $PROG scaffold, or point CDT_WQA_DIR at yours."
  adir="$(artifacts_dir)" || exit 1
  cd "$dir" 2>/dev/null || die "cannot enter harness dir: $dir"
  # Resolve playwright AFTER the cd: npx looks in ./node_modules, and the harness's copy is the one
  # that matches its config.
  pw="$(pw_cmd)"
  [ -n "$pw" ] || die "playwright is not installed in $dir — run: (cd $dir && npm install)"
  export CDT_QA_ARTIFACTS="$adir"
  [ -n "$app" ] && export APP="$app"
  [ -n "$br" ] && set -- "--project=$br" "$@"
  # --output= relocates Playwright's outputDir, so traces/video would land OUTSIDE the self-ignoring
  # artifacts root and become committable — silently breaking the guarantee that captures (which embed
  # network payloads, tokens and PII) can never be committed. Refuse it; CDT_QA_ARTIFACTS is the knob.
  for a in "$@"; do
    case "$a" in
      --output|--output=*)
        die "refusing '--output': it would move traces/video outside the gitignored artifacts root
       ($adir) and make captures committable. Set CDT_QA_ARTIFACTS to relocate them instead." ;;
    esac
  done
  note "harness:   $dir"
  note "artifacts: $adir"
  # Playwright's exit code IS the verdict — pass it straight through, never swallow or reinterpret it.
  # shellcheck disable=SC2086
  $pw test "$@"
  exit $?
}

# ----------------------------------------------------------------- trace ----
cmd_trace() {
  local f="${1:-}" pw
  [ -n "$f" ] || die "usage: $PROG trace <trace.zip>"
  case "$f" in -*) die "invalid trace path '$f' (leading '-' looks like a flag)" ;; esac
  [ -f "$f" ] || die "no such trace file: $f"
  pw="$(pw_cmd)"
  [ -n "$pw" ] || die "playwright not resolvable from $PWD — run this inside the harness (that is where its node_modules live)"
  note "opening the trace viewer — it blocks until you close the window"
  # shellcheck disable=SC2086
  $pw show-trace "$f"
  exit $?
}

# -------------------------------------------------------------- scaffold ----
# The script runs from BOTH ~/.claude/bin and the repo, so the templates dir is resolved through a
# candidate list (override -> beside the script -> user copy -> newest versioned plugin cache).
cmd_scaffold() {
  local out="" force=0 tdir="" c f dst files out_phys="" _dstdir="" wrote=0 failed=0
  while [ $# -gt 0 ]; do
    case "$1" in
      --dir)   out="${2:-}"; [ -n "$out" ] || die "--dir needs a path"
               case "$out" in *..*|-*) die "invalid --dir '$out' (no '..')" ;; esac; shift 2 ;;
      --force) force=1; shift ;;
      *) die "unknown flag: $1" ;;
    esac
  done
  [ -n "$out" ] || out="$PWD/qa-web"
  # A repository root is never the right target, with or without --force: the harness owns a
  # subdirectory. Cheap and exact for the commonest mistake; the ownership check below is the general
  # guard (a package in a monorepo has no .git of its own).
  if [ -e "$out/.git" ]; then
    die "refusing to scaffold into '$out' — that is a repository root, and the harness owns a
       subdirectory. Use: $PROG scaffold --dir $out/qa-web"
  fi
  for c in "${CDT_WQA_TEMPLATES:-}" "$SELF_DIR/../skills/web-qa/templates" "$CDT_HOME/skills/web-qa/templates"; do
    [ -n "$c" ] && [ -d "$c" ] && { tdir="$c"; break; }
  done
  # shellcheck disable=SC2012  # plugin cache dirs are semver names; sort -V picks the newest install
  [ -n "$tdir" ] || tdir="$(ls -d "$CDT_HOME"/plugins/cache/claude-dev-team/cdt/*/skills/web-qa/templates 2>/dev/null | sort -V | tail -1)"
  [ -n "$tdir" ] && [ -d "$tdir" ] \
    || die "harness templates not found (looked beside $SELF_DIR and under $CDT_HOME) — reinstall claude-dev-team, or set CDT_WQA_TEMPLATES."
  files="$(cd "$tdir" && find . -type f | sed 's|^\./||' | sort)"
  [ -n "$files" ] || die "no templates in $tdir"

  # POSITIVE FINGERPRINT, not marker-sniffing and not "is anything foreign here?".
  # Enumerating project markers (.git, package.json, go.mod …) is whack-a-mole: a package inside a
  # monorepo has NO .git of its own, and --force there destroys someone's project. But "holds a
  # foreign file" is also wrong: after onboarding a real harness holds apps/<id>.ts and .env.qa,
  # which would make --force refuse forever. The actual question is "is $out a web-qa harness?",
  # so ask that directly.
  # Checked on BOTH paths, not just --force. Gating it on --force made the fingerprint
  # SELF-ESTABLISHING: a plain scaffold plants playwright.config.ts + apps/types.ts into someone's
  # package (skipping the files that already exist), and a second run with --force then passes the
  # gate and overwrites their package.json/tsconfig.json — deps, scripts and TS path aliases gone.
  # An existing non-harness directory is never ours to write into, with or without --force.
  # `.gitignore` is excluded from the emptiness test because we never overwrite it, so a pre-made
  # dir holding only that is still ours to write into.
  if [ -d "$out" ] && [ -n "$(find "$out" -mindepth 1 -maxdepth 1 ! -name '.gitignore' 2>/dev/null | head -1)" ]; then
    if ! { [ -f "$out/playwright.config.ts" ] && [ -f "$out/apps/types.ts" ]; }; then
      die "refusing to scaffold into '$out' — it is not empty and is not a web-qa harness
       (no playwright.config.ts + apps/types.ts), so this would write into someone else's project.
       The harness owns its own subdirectory: $PROG scaffold --dir $out/qa-web"
    fi
  fi
  mkdir -p "$out" 2>/dev/null || die "cannot create $out"
  out_phys="$(cd "$out" 2>/dev/null && pwd -P)" || die "cannot resolve $out"
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    dst="$out/$f"
    # NEVER overwrite an existing .gitignore, not even with --force. Replacing a project's ignore
    # rules un-ignores whatever it was protecting (.env, *.pem, credentials.json) and stages live
    # secrets for commit. Losing our rules is recoverable; leaking a key is not.
    if [ "$f" = ".gitignore" ] && [ -e "$dst" ]; then
      echo "  skip (never overwritten) $dst"
      # .auth/ FIRST: it holds storageState — live session cookies for every role. Omitting it from
      # this list meant a user who followed the guidance verbatim staged an admin session token.
      note "NOTE: $dst already existed — add these yourself if missing: .auth/ (live session cookies —
       never commit), .env.qa, .claude/qa/, test-results/, playwright-report/"
      continue
    fi
    # A DIRECTORY where a template file belongs is a failure on BOTH paths. Checking it only after
    # the skip-exists branch meant that without --force it was reported as a benign "skip (exists)",
    # and the run still printed "harness in ..." and exited 0 with (say) support/auth.ts absent.
    if [ -d "$dst" ]; then echo "  FAILED $dst (a directory is in the way)" >&2; failed=$((failed+1)); continue; fi
    if [ -e "$dst" ] && [ "$force" != 1 ]; then echo "  skip (exists) $dst"; continue; fi
    mkdir -p "$(dirname "$dst")" 2>/dev/null
    # The file-level unlink below stops a symlinked FILE being written through, but a symlinked
    # PARENT DIRECTORY (e.g. apps/ -> /elsewhere) escapes it: the destination resolves outside $out
    # and we clobber someone else's file. Compare PHYSICAL paths and refuse anything that leaves.
    _dstdir="$(cd "$(dirname "$dst")" 2>/dev/null && pwd -P)"
    case "$_dstdir" in
      "$out_phys"|"$out_phys"/*) ;;
      *) echo "  FAILED $dst (resolves outside $out — a symlinked directory is in the path)" >&2
         failed=$((failed+1)); continue ;;
    esac
    # Unlink first: `cp` FOLLOWS a symlink and writes THROUGH it, so a pre-planted link named like a
    # template would clobber a file outside $out (and `find -type f` never lists it).
    rm -f "$dst" 2>/dev/null
    cp "$tdir/$f" "$dst" 2>/dev/null || { echo "  FAILED $dst" >&2; failed=$((failed+1)); continue; }
    echo "  wrote $dst"
    wrote=$((wrote+1))
  done <<EOF
$files
EOF
  # A partial copy must NOT report success: a half-written harness that exits 0 is exactly the fake
  # pass this tool exists to prevent.
  if [ "$failed" -gt 0 ]; then
    die "$failed of $((wrote+failed)) template file(s) could not be copied into $out — the harness is
       INCOMPLETE. Fix the cause (permissions? disk?) and re-run."
  fi
  [ "$wrote" -gt 0 ] || note "nothing written — every template already exists (re-run with --force to overwrite)"
  note "harness in $out (from $tdir)"
  note "next: (cd $out && npm install) then '$PROG doctor' from there"
}

usage() {
  cat <<EOF
$PROG — drive a real browser for autonomous QA. Every artifact path printed is absolute.

  $PROG doctor                            node/playwright/engines/MCP gate (exit 1 on any FAIL)
  $PROG browsers [--install]              which engines are installed; --install downloads them
  $PROG artifacts [--dir] [--clean]       print (or delete) this run's artifact dir
  $PROG scaffold [--dir <path>] [--force]         copy the shipped harness (default: ./qa-web)
                                                  then per its README: copy apps/example-*.ts to
                                                  apps/<your-id>.ts and register it in apps/index.ts
  $PROG test [--app <id>] [--browser chromium|firefox|webkit] [-- <playwright args>]
                                          run the harness; playwright's exit code is passed through
  $PROG trace <file>                      open a trace.zip in the playwright viewer (blocks)
  $PROG help                              this help

Environment:
  CDT_QA_ARTIFACTS   artifacts dir, shared with cdt-mobile-qa. Default <repo-or-cwd>/.claude/qa/web/<runid>.
  CDT_QA_RUNID       pin the run id. Otherwise the newest existing run is reused ('artifacts --clean'
                     or a new CDT_QA_RUNID starts a fresh one).
  CDT_WQA_DIR        harness dir for 'test'. Otherwise ./qa-web, then the current dir.
  CDT_WQA_TEMPLATES  override the scaffold templates dir.
  APP                app id the harness selects; '--app' sets it for one run.

Nothing here installs anything except 'browsers --install'. 'test' resolves playwright from the
harness's own node_modules, so run 'npm install' there first. Names allow letters, digits, '.', '_',
'-' only.
EOF
}

SUB="${1:-help}"; [ $# -gt 0 ] && shift

case "$SUB" in
  doctor)         cmd_doctor ;;
  browsers)       cmd_browsers "$@" ;;
  artifacts)      cmd_artifacts "$@" ;;
  scaffold)       cmd_scaffold "$@" ;;
  test)           cmd_test "$@" ;;
  trace)          cmd_trace "$@" ;;
  help|-h|--help) usage ;;
  *) die "unknown subcommand '$SUB' (try: $PROG help)" ;;
esac
