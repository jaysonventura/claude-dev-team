#!/usr/bin/env bash
# cdt-menubar — build, run, and manage the claude-dev-team menu bar monitor as "CDT Usage.app".
#   cdt-menubar install          build the .app into Applications + enable auto-start + launch (default)
#   cdt-menubar build            compile + bundle into "CDT Usage.app"
#   cdt-menubar start|stop|restart
#   cdt-menubar status           one-shot terminal readout (no GUI)
#   cdt-menubar install-login    enable auto-start at login (LaunchAgent)
#   cdt-menubar uninstall        remove the app + LaunchAgent
# Override the install location with CDT_MENUBAR_APPS (default: ~/Applications).
set +e

CDT_HOME="$HOME/.claude"
SRC="$CDT_HOME/claude-dev-team-menubar"
BIN="$CDT_HOME/bin"
APPS="${CDT_MENUBAR_APPS:-$HOME/Applications}"
APP_BUNDLE="$APPS/CDT Usage.app"
APP="$APP_BUNDLE/Contents/MacOS/cdt-menubar"
LABEL="com.jaysonventura.claude-dev-team.menubar"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"

find_src() {
  [ -f "$SRC/Package.swift" ] && return 0
  local cand
  cand=$(ls -d "$CDT_HOME"/plugins/cache/claude-dev-team/claude-dev-team/*/menubar 2>/dev/null | sort -V | tail -1)
  if [ -n "$cand" ] && [ -f "$cand/Package.swift" ]; then
    mkdir -p "$SRC" && cp -R "$cand/Package.swift" "$cand/Sources" "$SRC/" 2>/dev/null
    [ -f "$cand/Info.plist" ] && cp "$cand/Info.plist" "$SRC/" 2>/dev/null
    return 0
  fi
  return 1
}

plugin_version() {
  local pj
  pj=$(ls -d "$CDT_HOME"/plugins/cache/claude-dev-team/claude-dev-team/*/.claude-plugin/plugin.json 2>/dev/null | sort -V | tail -1)
  { [ -f "$pj" ] && python3 -c "import json;print(json.load(open('$pj'))['version'])" 2>/dev/null; } || echo "1.0.0"
}

sign_app() {
  local id="${CDT_SIGN_IDENTITY:-}"
  if [ -z "$id" ]; then
    id=$(security find-identity -v -p codesigning 2>/dev/null | grep -m1 "Developer ID Application" | sed -E 's/^.*"([^"]+)".*$/\1/')
    [ -z "$id" ] && id=$(security find-identity -v -p codesigning 2>/dev/null | grep -m1 -E "Apple Development|Apple Distribution|Developer ID" | sed -E 's/^.*"([^"]+)".*$/\1/')
  fi
  [ -z "$id" ] && { echo "Unsigned (no code-signing identity; works locally)."; return; }
  codesign --force --sign "$id" "$APP" 2>/dev/null
  codesign --force --sign "$id" "$APP_BUNDLE" 2>/dev/null && echo "Code-signed ✓"
}

build() {
  command -v swift >/dev/null 2>&1 || { echo "Swift not found. Install: xcode-select --install"; return 1; }
  find_src || { echo "Menu bar source not found — open a Claude Code session once to bootstrap it."; return 1; }
  echo "Building CDT Usage.app…"
  ( cd "$SRC" && swift build -c release ) || { echo "Build failed."; return 1; }
  mkdir -p "$APPS" "$APP_BUNDLE/Contents/MacOS" "$APP_BUNDLE/Contents/Resources"
  cp "$SRC/.build/release/cdt-menubar" "$APP" && chmod +x "$APP"
  [ -f "$SRC/Info.plist" ] && sed "s/__VERSION__/$(plugin_version)/g" "$SRC/Info.plist" > "$APP_BUNDLE/Contents/Info.plist"
  sign_app
  echo "Installed: $APP_BUNDLE"
}

start() {
  [ -x "$APP" ] || build || return 1
  pkill -f "$APP" 2>/dev/null
  open "$APP_BUNDLE" 2>/dev/null && echo "Launched — look for the CDT item in your menu bar." \
    || { nohup "$APP" >/dev/null 2>&1 & echo "Started."; }
}

stop() { pkill -f "$APP" 2>/dev/null && echo "Stopped." || echo "Not running."; }

status() { [ -x "$APP" ] || build || return 1; "$APP" --once; }

install_login() {
  [ -x "$APP" ] || build || return 1
  rm -f "$CDT_HOME/.cdt-menubar-disabled" 2>/dev/null
  launchctl unload "$PLIST" 2>/dev/null; rm -f "$PLIST"   # remove any legacy LaunchAgent
  pkill -f "$APP" 2>/dev/null
  # The app registers itself for launch-at-login via SMAppService (shown as "CDT Usage"), so just launch it.
  open "$APP_BUNDLE" 2>/dev/null && echo "Launched + registered for login as CDT Usage."
}

uninstall() {
  [ -x "$APP" ] && "$APP" --unregister >/dev/null 2>&1   # remove the login item (SMAppService)
  launchctl unload "$PLIST" 2>/dev/null; rm -f "$PLIST"  # legacy LaunchAgent cleanup
  pkill -f "$APP" 2>/dev/null
  rm -rf "$APP_BUNDLE"
  rm -f "$BIN/cdt-menubar-app" 2>/dev/null
  touch "$CDT_HOME/.cdt-menubar-disabled" 2>/dev/null
  echo "Uninstalled (login item + CDT Usage.app removed). Re-enable: cdt-menubar install"
}

case "${1:-install}" in
  build)                 build ;;
  start)                 start ;;
  stop)                  stop ;;
  restart)               stop; start ;;
  status|check|once)     status ;;
  install-login|login)   install_login ;;
  uninstall|remove)      uninstall ;;
  install)               build && install_login ;;
  *) echo "usage: cdt-menubar {install|build|start|stop|restart|status|install-login|uninstall}"; exit 1 ;;
esac
