#!/usr/bin/env bash
# cdt-mobile-qa — the Android device control plane for autonomous mobile QA.
#
# One thin adb wrapper per capability an agent needs to drive a real device or emulator, plus a
# `doctor` gate, an `appium` server lifecycle, and `scaffold` for the shipped harness. Every capture
# writes into a per-run artifacts dir and prints its ABSOLUTE path on stdout, so an agent can parse
# it. Honest by construction: if adb — or the device — is missing, the subcommand fails loudly with
# a fix hint and a non-zero exit. It NEVER prints a success line for something that did not happen;
# that is the whole point of this feature.
#
# Device targeting: $CDT_MQA_DEVICE (an adb serial). Unset with exactly one device attached -> that
# one. Unset with several attached -> it refuses and lists the serials rather than guessing.
set +e

PROG="cdt-mobile-qa"
SELF_DIR="$(cd "$(dirname "$0")" 2>/dev/null && pwd)"
CDT_HOME="${CDT_HOME:-$HOME/.claude}"
REMOTE_UI="/sdcard/cdt-mqa-ui.xml"
REMOTE_MP4="/sdcard/cdt-mqa-record.mp4"
SERIAL=""

die()  { echo "$PROG: $*" >&2; exit 1; }
note() { echo "$PROG: $*"; }

# Install hint for the detected package manager — same style as deps.sh.
adb_hint() {
  if   command -v brew    >/dev/null 2>&1; then echo "brew install --cask android-platform-tools"
  elif command -v apt-get >/dev/null 2>&1; then echo "sudo apt-get install -y android-tools-adb"
  elif command -v dnf     >/dev/null 2>&1; then echo "sudo dnf install -y android-tools"
  elif command -v pacman  >/dev/null 2>&1; then echo "sudo pacman -S --noconfirm android-tools"
  elif command -v winget  >/dev/null 2>&1; then echo "winget install -e --id Google.PlatformTools"
  else echo "get platform-tools from https://developer.android.com/studio/releases/platform-tools"
  fi
}

# Names that become file/dir components. Blocks path traversal and option injection (same posture
# as cdt-worktree's valid_name).
safe_name() {
  case "$1" in
    ''|-*|*..*|*/*|*[!A-Za-z0-9._-]*)
      die "invalid name '$1' — use letters, digits, '.', '_', '-' (no '/', no '..')." ;;
  esac
}

# Strings that reach the DEVICE shell. adb's non-interactive `shell` joins argv into one string that
# the device's sh re-parses, so local quoting is not enough: `reset 'com.x;rm -rf /sdcard/DCIM'` would
# run both halves on the device. Package names and permissions are a known charset — enforce it.
safe_ident() {
  case "$1" in
    ''|*[!A-Za-z0-9._]*)
      die "invalid identifier '$1' — package/permission names are letters, digits, '.' and '_' only." ;;
  esac
}

online_serials() { adb devices 2>/dev/null | awk 'NR>1 && $2=="device" {print $1}'; }
device_line() {
  echo "$1 — $(adb -s "$1" shell getprop ro.product.model 2>/dev/null | tr -d '\r') (API $(adb -s "$1" shell getprop ro.build.version.sdk 2>/dev/null | tr -d '\r'))"
}

# Resolve the target device ONCE, then every adb call goes through _adb.
resolve_device() {
  [ -n "$SERIAL" ] && return 0
  command -v adb >/dev/null 2>&1 || die "adb not found — install it: $(adb_hint)"
  if [ -n "${CDT_MQA_DEVICE:-}" ]; then SERIAL="$CDT_MQA_DEVICE"; return 0; fi
  local list n
  list="$(online_serials)"
  n="$(printf '%s\n' "$list" | grep -c .)"
  [ "$n" -eq 0 ] && die "no device online — boot an emulator or plug in a device with USB debugging on, then: $PROG devices"
  [ "$n" -gt 1 ] && die "$n devices attached — set CDT_MQA_DEVICE to one of:
$(printf '%s\n' "$list" | sed 's/^/       /')"
  SERIAL="$list"
}
_adb() { resolve_device; adb -s "$SERIAL" "$@"; }

# One run = one dir, so a multi-command scenario keeps its artifacts together: reuse the newest
# existing run, start a fresh one with `artifacts --clean` or by exporting CDT_MQA_RUNID.
artifacts_dir() {
  local root dir run
  if [ -n "${CDT_QA_ARTIFACTS:-}" ]; then
    dir="$CDT_QA_ARTIFACTS"
  elif [ -n "${CDT_MQA_ARTIFACTS:-}" ]; then
    dir="$CDT_MQA_ARTIFACTS"
  else
    root="$(git rev-parse --show-toplevel 2>/dev/null)"; [ -n "$root" ] || root="$PWD"
    root="$root/.claude/qa/mobile"
    if [ -n "${CDT_MQA_RUNID:-}" ]; then
      run="$CDT_MQA_RUNID"; safe_name "$run"
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
  # Self-ignoring: captures are screenshots, video and logcat — they carry session tokens, OTPs and
  # PII and must never be committable. A repo-level .gitignore rule cannot cover a custom
  # CDT_MQA_ARTIFACTS pointing elsewhere, so the artifacts root ignores itself (including this file).
  # ONLY for a dir we just created, or one that is empty. Writing '*' into a pre-existing directory
  # would silently hide whatever already lives there — if CDT_MQA_ARTIFACTS points at real source,
  # that erases it from `git status`. Never change what git tracks in a directory we do not own.
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

# `appium` on PATH, else an already-installed npx copy. Never installs anything.
appium_cmd() {
  if command -v appium >/dev/null 2>&1; then echo "appium"
  elif command -v npx >/dev/null 2>&1 && npx --no-install appium --version >/dev/null 2>&1; then echo "npx --no-install appium"
  fi
}

# ---------------------------------------------------------------- doctor ----
DOC_BAD=0
P() { echo "  [PASS] $1"; }
W() { echo "  [WARN] $1 — $2"; }
F() { echo "  [FAIL] $1 — $2"; DOC_BAD=$((DOC_BAD+1)); }

cmd_doctor() {
  local list n s ac
  echo "$PROG — doctor  (device target: ${CDT_MQA_DEVICE:-auto})"
  if command -v adb >/dev/null 2>&1; then
    P "adb present — $(adb version 2>/dev/null | head -1)"
    if adb start-server >/dev/null 2>&1; then
      P "adb server reachable"
      list="$(online_serials)"; n="$(printf '%s\n' "$list" | grep -c .)"
      if [ "$n" -eq 0 ]; then
        F "no device or emulator online" "boot an emulator, or plug in a device with USB debugging enabled"
      else
        while IFS= read -r s; do
          [ -n "$s" ] || continue
          P "device $(device_line "$s")"
        done <<EOF
$list
EOF
        if [ "$n" -gt 1 ] && [ -z "${CDT_MQA_DEVICE:-}" ]; then
          W "$n devices attached with CDT_MQA_DEVICE unset" "export CDT_MQA_DEVICE=<serial> — device commands refuse to guess"
        fi
      fi
    else
      F "adb server not reachable" "run: adb kill-server && adb start-server"
    fi
  else
    F "adb not found" "install it: $(adb_hint)"
  fi

  if command -v node >/dev/null 2>&1; then P "node $(node --version 2>/dev/null)"
  else W "node not found" "appium needs Node 18+ — install it (brew install node), or drive the device with adb only"; fi

  ac="$(appium_cmd)"
  if [ -n "$ac" ]; then
    # shellcheck disable=SC2086
    P "appium $($ac --version 2>/dev/null | tail -1)"
    # shellcheck disable=SC2086
    if $ac driver list --installed 2>&1 | grep -q uiautomator2; then P "uiautomator2 driver installed"
    else W "uiautomator2 driver not installed" "run: appium driver install uiautomator2"; fi
  else
    W "appium not found" "npm i -g appium, then: appium driver install uiautomator2"
  fi

  if command -v claude >/dev/null 2>&1; then
    if claude mcp list 2>/dev/null | grep -qiE 'appium|mobile'; then P "mobile MCP server wired"
    else W "no appium/mobile MCP server wired" "optional, $PROG drives adb directly; add one with: claude mcp add"; fi
  else
    W "claude CLI not on PATH" "cannot check MCP wiring (optional)"
  fi

  echo
  [ "$DOC_BAD" -eq 0 ] && { note "ready — no FAIL lines."; exit 0; }
  note "$DOC_BAD check(s) FAILED — device work will not run until they are fixed."
  exit 1
}

# --------------------------------------------------------------- devices ----
cmd_devices() {
  command -v adb >/dev/null 2>&1 || die "adb not found — install it: $(adb_hint)"
  adb devices -l
  local s
  while IFS= read -r s; do
    [ -n "$s" ] || continue
    echo "  $(device_line "$s")"
  done <<EOF
$(online_serials)
EOF
}

# --------------------------------------------------------------- app ops ----
cmd_install() {
  local apk="" a
  for a in "$@"; do
    case "$a" in
      -*) die "unknown flag: $a (install always replaces; for clean state use: $PROG reset <pkg>)" ;;
      *)  [ -n "$apk" ] && die "only one apk allowed (got '$apk' and '$a')."; apk="$a" ;;
    esac
  done
  [ -n "$apk" ] || die "usage: $PROG install <apk>"
  [ -f "$apk" ] || die "no such apk: $apk"
  # `adb install` prints Success/Failure and has historically exited 0 on failure — trust the output.
  case "$(_adb install -r -g "$apk" 2>&1 | tr -d '\r')" in
    *Success*) note "installed $apk on $SERIAL" ;;
    *) die "adb install did not report Success for $apk" ;;
  esac
}

cmd_launch() {
  local pkg="${1:-}" act="${2:-}" i=0
  [ -n "$pkg" ] || die "usage: $PROG launch <pkg> [activity]"
  safe_ident "$pkg"
  [ -n "$act" ] && safe_ident "$act"
  if [ -n "$act" ]; then
    _adb shell am start -W -n "$pkg/$act" || die "am start failed for $pkg/$act"
  else
    _adb shell monkey -p "$pkg" -c android.intent.category.LAUNCHER 1 >/dev/null 2>&1 \
      || die "no launchable activity for $pkg (is it installed?)"
  fi
  while [ "$i" -lt 15 ]; do
    if _adb shell dumpsys window 2>/dev/null | grep -E 'mCurrentFocus|mFocusedApp' | grep -qF "$pkg"; then
      note "$pkg is in the foreground"; return 0
    fi
    i=$((i+1)); sleep 1
  done
  die "$pkg never reached the foreground (15s) — it may have crashed: $PROG logcat --pkg $pkg --crash"
}

cmd_stop() {
  [ -n "${1:-}" ] || die "usage: $PROG stop <pkg>"
  safe_ident "$1"
  _adb shell am force-stop "$1" || die "am force-stop failed for $1"
  note "stopped $1"
}

cmd_reset() {
  [ -n "${1:-}" ] || die "usage: $PROG reset <pkg>"
  safe_ident "$1"
  # `pm clear` prints "Success"/"Failed" and can exit 0 on a no-op, so trust the OUTPUT, not the code —
  # claiming "fresh state" without it is the fake pass this tool exists to prevent.
  case "$(_adb shell pm clear "$1" 2>&1 | tr -d '\r')" in
    *Success*) note "cleared all data for $1 — fresh state" ;;
    *) die "pm clear did not report Success for $1 (is it installed?) — state is NOT clean" ;;
  esac
}

# -------------------------------------------------------------- captures ----
cmd_shot() {
  local name="${1:-shot-$(date +%H%M%S)}" dir out
  safe_name "$name"
  dir="$(artifacts_dir)" || exit 1
  out="$dir/$name.png"
  _adb exec-out screencap -p > "$out"
  [ -s "$out" ] || { rm -f "$out"; die "screenshot failed (empty capture) — is the screen on?"; }
  echo "$out"
}

cmd_record() {
  local sub="${1:-}" name dir out
  [ $# -gt 0 ] && shift
  name="${1:-record}"; safe_name "$name"
  dir="$(artifacts_dir)" || exit 1
  resolve_device
  case "$sub" in
    start)
      adb -s "$SERIAL" shell rm -f "$REMOTE_MP4" >/dev/null 2>&1
      nohup adb -s "$SERIAL" shell screenrecord "$REMOTE_MP4" >/dev/null 2>&1 &
      sleep 2
      adb -s "$SERIAL" shell "pgrep screenrecord || pidof screenrecord" >/dev/null 2>&1 \
        || die "screenrecord did not start (needs Android 4.4+ and a real screen)"
      note "recording on $SERIAL — stop it with: $PROG record stop [name]"
      ;;
    stop)
      adb -s "$SERIAL" shell "pkill -INT screenrecord || killall -INT screenrecord" >/dev/null 2>&1
      sleep 2   # screenrecord needs a moment to finalise the mp4 container
      out="$dir/$name.mp4"
      adb -s "$SERIAL" pull "$REMOTE_MP4" "$out" >/dev/null 2>&1 \
        || die "nothing to pull from $REMOTE_MP4 (did you run '$PROG record start'?)"
      adb -s "$SERIAL" shell rm -f "$REMOTE_MP4" >/dev/null 2>&1
      [ -s "$out" ] || { rm -f "$out"; die "the recording was empty"; }
      echo "$out"
      ;;
    *) die "usage: $PROG record start|stop [name]" ;;
  esac
}

cmd_ui() {
  local json=0 a dir xml
  for a in "$@"; do case "$a" in --json) json=1 ;; *) die "unknown flag: $a" ;; esac; done
  dir="$(artifacts_dir)" || exit 1
  xml="$dir/ui.xml"
  # Clear the previous dump FIRST (as cmd_record does). Without this, a dump that fails in a way adb
  # does not report as non-zero leaves the last run's XML on the device and we pull a STALE tree —
  # which the skill tells the agent to treat as fact. A stale tree is a fabricated observation.
  _adb shell rm -f "$REMOTE_UI" >/dev/null 2>&1
  _adb shell uiautomator dump "$REMOTE_UI" >/dev/null 2>&1 \
    || die "uiautomator dump failed (screen off, or a secure window is showing)"
  _adb shell test -s "$REMOTE_UI" >/dev/null 2>&1 \
    || die "uiautomator produced no dump on the device (screen off, or a secure window is showing)"
  _adb pull "$REMOTE_UI" "$xml" >/dev/null 2>&1 || die "could not pull the UI dump off the device"
  [ -s "$xml" ] || die "the UI dump was empty"
  echo "$xml"
  [ "$json" = 1 ] || return 0
  command -v python3 >/dev/null 2>&1 || die "python3 not found — required for --json"
  python3 - "$xml" > "$dir/ui.json" <<'PY' || die "could not parse the UI dump"
import json, sys, xml.etree.ElementTree as ET
out = []
for n in ET.parse(sys.argv[1]).getroot().iter('node'):
    g, cls = n.get, n.get('class') or ''
    if not (g('clickable') == 'true' or g('long-clickable') == 'true' or g('checkable') == 'true'
            or g('scrollable') == 'true' or 'EditText' in cls):
        continue
    out.append({'id': g('resource-id') or '', 'desc': g('content-desc') or '',
                'text': g('text') or '', 'class': cls.split('.')[-1],
                'bounds': g('bounds') or '', 'clickable': g('clickable') == 'true'})
json.dump(out, sys.stdout, separators=(',', ':'))
PY
  echo "$dir/ui.json"
  cat "$dir/ui.json"; echo
}

cmd_logcat() {
  local since="" pkg="" crash=0 dir out pid=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --since) since="${2:-}"; [ -n "$since" ] || die "--since needs a timestamp (e.g. '01-31 14:00:00.000' or an epoch)"; shift 2 ;;
      --pkg)   pkg="${2:-}";   [ -n "$pkg" ]   || die "--pkg needs a package name"; shift 2 ;;
      --crash) crash=1; shift ;;
      *) die "unknown flag: $1" ;;
    esac
  done
  dir="$(artifacts_dir)" || exit 1
  out="$dir/logcat-$(date +%H%M%S).log"
  [ -n "$pkg" ] && safe_ident "$pkg"
  resolve_device
  [ -n "$pkg" ] && pid="$(adb -s "$SERIAL" shell pidof "$pkg" 2>/dev/null | tr -d '\r' | awk '{print $1}')"
  set -- -d
  [ "$crash" = 1 ] && set -- "$@" -b crash
  [ -n "$since" ] && set -- "$@" -T "$since"
  [ -n "$pid" ]   && set -- "$@" "--pid=$pid"
  if [ -n "$pkg" ] && [ -z "$pid" ]; then
    # Not running: no pid to filter on, so fall back to a name match over the buffer. This is the
    # app-CRASHED path, so it must not swallow an adb failure: in a pipeline the exit status is
    # grep's, and an empty log would read as "no errors" when adb never ran.
    adb -s "$SERIAL" logcat "$@" > "$dir/.logcat.raw" 2>/dev/null \
      || { rm -f "$dir/.logcat.raw"; die "adb logcat failed"; }
    grep -F "$pkg" "$dir/.logcat.raw" > "$out"
    rm -f "$dir/.logcat.raw"
  else
    adb -s "$SERIAL" logcat "$@" > "$out" 2>/dev/null || die "adb logcat failed"
  fi
  echo "$out"
  tail -20 "$out"
}

# --------------------------------------------------------- device state ----
cmd_net() {
  case "${1:-}" in
    on)
      _adb shell svc data enable >/dev/null 2>&1 || die "svc data enable failed (some devices require root)"
      _adb shell svc wifi enable >/dev/null 2>&1 || die "svc wifi enable failed (some devices require root)"
      note "mobile data + wifi ENABLED on $SERIAL"
      ;;
    off)
      note "WARNING: this changes real device state — restore it with '$PROG net on'"
      _adb shell svc data disable >/dev/null 2>&1 || die "svc data disable failed (some devices require root)"
      _adb shell svc wifi disable >/dev/null 2>&1 || die "svc wifi disable failed (some devices require root)"
      note "mobile data + wifi DISABLED on $SERIAL"
      ;;
    *) die "usage: $PROG net on|off" ;;
  esac
}

cmd_perm() {
  local act="${1:-}" pkg="${2:-}" p
  case "$act" in grant|revoke) ;; *) die "usage: $PROG perm grant|revoke <pkg> <perm...>" ;; esac
  [ -n "$pkg" ] || die "usage: $PROG perm $act <pkg> <perm...>"
  shift 2
  [ $# -gt 0 ] || die "give at least one permission (e.g. android.permission.CAMERA)"
  safe_ident "$pkg"
  for p in "$@"; do
    safe_ident "$p"
    _adb shell pm "$act" "$pkg" "$p" >/dev/null 2>&1 \
      || die "pm $act failed for $p (not a runtime permission, or not declared in the manifest?)"
    note "$act $p -> $pkg"
  done
}

# ------------------------------------------------------------- artifacts ----
cmd_artifacts() {
  local clean=0 a dir root
  for a in "$@"; do case "$a" in --dir) : ;; --clean) clean=1 ;; *) die "unknown flag: $a" ;; esac; done
  dir="$(artifacts_dir)" || exit 1
  if [ "$clean" = 1 ]; then
    # Containment, not a substring match. `*/mobile-qa/*` matched ANY path with a mobile-qa segment,
    # so `CDT_MQA_ARTIFACTS=<proj>/mobile-qa/src artifacts --clean` rm -rf'd real source.
    # Only a run dir DIRECTLY under this repo's own artifacts root may be deleted.
    root="$(git rev-parse --show-toplevel 2>/dev/null)"; [ -n "$root" ] || root="$PWD"
    root="$root/.claude/qa/mobile"
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

# ---------------------------------------------------------------- appium ----
cmd_appium() {
  local sub="${1:-status}" dir pidf log ac pid i
  dir="$(artifacts_dir)" || exit 1
  pidf="$dir/appium.pid"; log="$dir/appium.log"; pid="$(cat "$pidf" 2>/dev/null)"
  case "$sub" in
    start)
      if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then note "appium already running (pid $pid) — log: $log"; return 0; fi
      ac="$(appium_cmd)"
      [ -n "$ac" ] || die "appium not found — install it: npm i -g appium (then: appium driver install uiautomator2)"
      # shellcheck disable=SC2086
      # Own process group so `stop` can kill the whole tree (npx spawns the server as a child).
      set -m 2>/dev/null
      nohup $ac > "$log" 2>&1 &
      pid=$!
      set +m 2>/dev/null
      echo "$pid" > "$pidf"
      sleep 3
      kill -0 "$pid" 2>/dev/null || { rm -f "$pidf"; die "appium exited immediately — see $log"; }
      note "appium started (pid $pid)"
      echo "$log"
      ;;
    stop)
      if [ -z "$pid" ] || ! kill -0 "$pid" 2>/dev/null; then die "appium is not running (no live pid in $pidf)"; fi
      # On the npx path $! is npx's pid, and the real server is its child — killing the parent alone
      # leaves the server listening while we claim it stopped. Kill the process GROUP, then verify.
      kill -- "-$pid" 2>/dev/null || kill "$pid" 2>/dev/null || die "could not stop appium (pid $pid)"
      i=0
      while [ "$i" -lt 10 ]; do kill -0 "$pid" 2>/dev/null || break; i=$((i+1)); sleep 1; done
      if kill -0 "$pid" 2>/dev/null; then
        kill -9 -- "-$pid" 2>/dev/null || kill -9 "$pid" 2>/dev/null
        sleep 1
      fi
      kill -0 "$pid" 2>/dev/null && die "appium (pid $pid) is STILL running — stop it manually"
      rm -f "$pidf"; note "appium stopped (pid $pid)"
      ;;
    status)
      if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then note "appium RUNNING (pid $pid) — log: $log"
      else note "appium NOT running"; return 1; fi
      ;;
    *) die "usage: $PROG appium start|stop|status" ;;
  esac
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
  [ -n "$out" ] || out="$PWD/qa"
  # A repository root is never the right target, with or without --force: the harness owns a
  # subdirectory. Cheap and exact for the commonest mistake; the ownership check below is the general
  # guard (a Gradle module in a monorepo has no .git of its own).
  if [ -e "$out/.git" ]; then
    die "refusing to scaffold into '$out' — that is a repository root, and the harness owns a
       subdirectory. Use: $PROG scaffold --dir $out/qa"
  fi
  for c in "${CDT_MQA_TEMPLATES:-}" "$SELF_DIR/../skills/mobile-qa/templates" "$CDT_HOME/skills/mobile-qa/templates"; do
    [ -n "$c" ] && [ -d "$c" ] && { tdir="$c"; break; }
  done
  # shellcheck disable=SC2012  # plugin cache dirs are semver names; sort -V picks the newest install
  [ -n "$tdir" ] || tdir="$(ls -d "$CDT_HOME"/plugins/cache/claude-dev-team/cdt/*/skills/mobile-qa/templates 2>/dev/null | sort -V | tail -1)"
  [ -n "$tdir" ] && [ -d "$tdir" ] \
    || die "harness templates not found (looked beside $SELF_DIR and under $CDT_HOME) — reinstall claude-dev-team, or set CDT_MQA_TEMPLATES."
  files="$(cd "$tdir" && find . -type f | sed 's|^\./||' | sort)"
  [ -n "$files" ] || die "no templates in $tdir"

  # POSITIVE FINGERPRINT, not marker-sniffing and not "is anything foreign here?".
  # Enumerating project markers (.git, package.json, build.gradle, pubspec.yaml, go.mod …) is
  # whack-a-mole — a Gradle Android module in a monorepo has NO .git and NO package.json, and that is
  # this tool's primary target repo. But "holds a foreign file" is also wrong: after the documented
  # onboarding a real harness holds apps/<id>.ts and .env.qa, which would make --force refuse forever.
  # The actual question is "is $out a harness?", so ask that directly.
  # Checked on BOTH paths. Gating it on --force made the fingerprint SELF-ESTABLISHING: a plain
  # scaffold plants wdio.conf.ts + apps/types.ts into someone's package, and a second run with
  # --force then passes the gate and overwrites their package.json/tsconfig.json.
  # `.gitignore` is excluded from the emptiness test because we never overwrite it, so a pre-made
  # dir holding only that is still ours to write into.
  if [ -d "$out" ] && [ -n "$(find "$out" -mindepth 1 -maxdepth 1 ! -name '.gitignore' 2>/dev/null | head -1)" ]; then
    if ! { [ -f "$out/wdio.conf.ts" ] && [ -f "$out/apps/types.ts" ]; }; then
      die "refusing to scaffold into '$out' — it is not empty and is not a mobile-qa harness
       (no wdio.conf.ts + apps/types.ts), so this would write into someone else's project.
       The harness owns its own subdirectory: $PROG scaffold --dir $out/qa"
    fi
  fi
  mkdir -p "$out" 2>/dev/null || die "cannot create $out"
  out_phys="$(cd "$out" 2>/dev/null && pwd -P)" || die "cannot resolve $out"
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    dst="$out/$f"
    # NEVER overwrite an existing .gitignore, not even with --force. Replacing a project's ignore
    # rules un-ignores whatever it was protecting (.env, local.properties, *.keystore) and stages
    # live secrets for commit. Losing our rules is recoverable; leaking a key is not.
    if [ "$f" = ".gitignore" ] && [ -e "$dst" ]; then
      echo "  skip (never overwritten) $dst"
      note "NOTE: $dst already existed — add these yourself if missing: .env.qa, .claude/qa/"
      continue
    fi
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
       INCOMPLETE. Fix the cause (permissions? disk?) and re-run with --force."
  fi
  [ "$wrote" -gt 0 ] || note "nothing written — every template already exists (re-run with --force to overwrite)"
  note "harness in $out (from $tdir)"
}

usage() {
  cat <<EOF
$PROG — drive a real Android device/emulator for autonomous QA. Every capture prints its path.

  $PROG doctor                            adb/appium/driver/node/device/MCP gate (exit 1 on any FAIL)
  $PROG devices                           attached devices with model + API level
  $PROG install <apk>                     adb install -r -g (replaces; grants runtime permissions)
  $PROG launch <pkg> [activity]           start it and wait for the window (fails if it never focuses)
  $PROG stop <pkg>                        am force-stop
  $PROG reset <pkg>                       pm clear — fresh state for the next scenario
  $PROG shot [name]                       screenshot -> artifacts/<name>.png
  $PROG record start|stop [name]          screen recording -> artifacts/<name>.mp4
  $PROG ui [--json]                       UI dump -> ui.xml (--json also emits interactive nodes only)
  $PROG logcat [--since <ts>] [--pkg <pkg>] [--crash]   logcat -> artifacts, prints path + last lines
  $PROG net on|off                        toggle mobile data + wifi (off = offline scenarios)
  $PROG perm grant|revoke <pkg> <perm...> pm grant / pm revoke
  $PROG artifacts [--dir] [--clean]       print (or delete) this run's artifact dir
  $PROG appium start|stop|status          local appium server (background, pidfile, log in artifacts)
  $PROG scaffold [--dir <path>] [--force]         copy the shipped harness (default: ./qa)
                                                  then per its README: copy apps/example-*.ts to
                                                  apps/<your-id>.ts and register it in apps/index.ts
  $PROG help                              this help

Environment:
  CDT_MQA_DEVICE     adb serial to target. Required when more than one device is attached.
  CDT_QA_ARTIFACTS   artifacts dir (shared with cdt-web-qa). Default <repo>/.claude/qa/mobile/<runid>.
                     CDT_MQA_ARTIFACTS is still honoured for back-compat.
  CDT_MQA_RUNID      pin the run id. Otherwise the newest existing run is reused ('artifacts --clean'
                     or a new CDT_MQA_RUNID starts a fresh one).
  CDT_MQA_TEMPLATES  override the scaffold templates dir.

'net off' and 'reset' change real device state. Names allow letters, digits, '.', '_', '-' only.
EOF
}

SUB="${1:-help}"; [ $# -gt 0 ] && shift

# Resolve the device BEFORE dispatch for every subcommand that touches one. Doing it lazily inside
# _adb meant a "no device" / "which device?" refusal died silently whenever the caller had already
# redirected stderr (e.g. `adb shell pm clear ... 2>/dev/null`) — a silent non-zero exit is exactly
# the fake-pass this tool exists to prevent.
# Validate device-bound identifiers BEFORE resolving a device: a malformed package name is wrong
# regardless of what is plugged in, and this keeps the charset guard reachable (and testable) on a
# machine with no device attached. The per-command safe_ident calls remain as defence in depth.
case "$SUB" in
  launch)            [ -n "${1:-}" ] && safe_ident "$1"; [ -n "${2:-}" ] && safe_ident "$2" ;;
  stop|reset)        [ -n "${1:-}" ] && safe_ident "$1" ;;
  perm)              # $1 is grant|revoke; $2 is the package; $3.. are the permissions
                     _i=0; for _a in "$@"; do
                       _i=$((_i+1)); [ "$_i" -eq 1 ] && continue
                       [ -n "$_a" ] && safe_ident "$_a"
                     done ;;
  shot)              [ -n "${1:-}" ] && safe_name  "$1" ;;
  record)            [ -n "${2:-}" ] && safe_name  "$2" ;;
esac

case "$SUB" in
  install|launch|stop|reset|shot|record|ui|logcat|net|perm) resolve_device ;;
esac

case "$SUB" in
  doctor)         cmd_doctor ;;
  devices)        cmd_devices ;;
  install)        cmd_install "$@" ;;
  launch)         cmd_launch "$@" ;;
  stop)           cmd_stop "$@" ;;
  reset)          cmd_reset "$@" ;;
  shot)           cmd_shot "$@" ;;
  record)         cmd_record "$@" ;;
  ui)             cmd_ui "$@" ;;
  logcat)         cmd_logcat "$@" ;;
  net)            cmd_net "$@" ;;
  perm)           cmd_perm "$@" ;;
  artifacts)      cmd_artifacts "$@" ;;
  appium)         cmd_appium "$@" ;;
  scaffold)       cmd_scaffold "$@" ;;
  help|-h|--help) usage ;;
  *) die "unknown subcommand '$SUB' (try: $PROG help)" ;;
esac
