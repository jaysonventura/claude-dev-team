#!/usr/bin/env bash
# cdt-menubar — build, run, and manage the claude-dev-team menu bar usage monitor (native Swift).
#   cdt-menubar install          build + enable auto-start + launch (default)
#   cdt-menubar build            compile the Swift app
#   cdt-menubar start|stop|restart
#   cdt-menubar status           one-shot terminal readout (no GUI)
#   cdt-menubar install-login    enable auto-start at login (LaunchAgent)
#   cdt-menubar uninstall        remove LaunchAgent + app binary
set +e

CDT_HOME="$HOME/.claude"
SRC="$CDT_HOME/claude-dev-team-menubar"
BIN="$CDT_HOME/bin"
APP="$BIN/cdt-menubar-app"
LABEL="com.jaysonventura.claude-dev-team.menubar"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"

find_src() {
  [ -f "$SRC/Package.swift" ] && return 0
  local cand
  cand=$(ls -d "$CDT_HOME"/plugins/cache/claude-dev-team/claude-dev-team/*/menubar 2>/dev/null | sort -V | tail -1)
  if [ -n "$cand" ] && [ -f "$cand/Package.swift" ]; then
    mkdir -p "$SRC" && cp -R "$cand/Package.swift" "$cand/Sources" "$SRC/" 2>/dev/null && return 0
  fi
  return 1
}

# Code-sign with a stable identity if one exists, so the Keychain approval persists across rebuilds
# (an ad-hoc signature changes every build and re-prompts). Override with CDT_SIGN_IDENTITY.
sign_app() {
  local id="${CDT_SIGN_IDENTITY:-}"
  if [ -z "$id" ]; then
    id=$(security find-identity -v -p codesigning 2>/dev/null | grep -m1 "Developer ID Application" | sed -E 's/^.*"([^"]+)".*$/\1/')
    [ -z "$id" ] && id=$(security find-identity -v -p codesigning 2>/dev/null | grep -m1 -E "Apple Development|Apple Distribution|Developer ID" | sed -E 's/^.*"([^"]+)".*$/\1/')
  fi
  if [ -n "$id" ]; then
    codesign --force --sign "$id" "$APP" 2>/dev/null && echo "Signed: $id" || echo "Sign failed — running unsigned."
  else
    echo "Unsigned (no code-signing identity found; works locally, but Keychain may re-prompt on rebuilds)."
  fi
}

build() {
  if ! command -v swift >/dev/null 2>&1; then
    echo "Swift toolchain not found. Install it with:  xcode-select --install"; return 1
  fi
  find_src || { echo "Menu bar source not found — open a Claude Code session once to bootstrap it."; return 1; }
  echo "Building cdt-menubar (swift build -c release)…"
  ( cd "$SRC" && swift build -c release ) || { echo "Build failed."; return 1; }
  mkdir -p "$BIN"
  cp "$SRC/.build/release/cdt-menubar" "$APP" && chmod +x "$APP"
  sign_app
  echo "Built: $APP"
}

start() {
  [ -x "$APP" ] || build || return 1
  pkill -f "$APP" 2>/dev/null
  nohup "$APP" >/dev/null 2>&1 &
  echo "Started — look for the ▓ icon in your menu bar."
}

stop() { pkill -f "$APP" 2>/dev/null && echo "Stopped." || echo "Not running."; }

status() { [ -x "$APP" ] || build || return 1; "$APP" --once; }

install_login() {
  [ -x "$APP" ] || build || return 1
  rm -f "$CDT_HOME/.cdt-menubar-disabled" 2>/dev/null   # re-enable auto-install
  mkdir -p "$HOME/Library/LaunchAgents"
  cat > "$PLIST" <<PL
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>Label</key><string>$LABEL</string>
  <key>ProgramArguments</key><array><string>$APP</string></array>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><false/>
  <key>ProcessType</key><string>Interactive</string>
</dict></plist>
PL
  launchctl unload "$PLIST" 2>/dev/null
  launchctl load "$PLIST" 2>/dev/null && echo "Auto-start enabled at login (LaunchAgent: $LABEL)."
}

uninstall() {
  launchctl unload "$PLIST" 2>/dev/null
  rm -f "$PLIST"
  pkill -f "$APP" 2>/dev/null
  rm -f "$APP"
  touch "$CDT_HOME/.cdt-menubar-disabled" 2>/dev/null   # don't auto-reinstall on next session
  echo "Uninstalled (LaunchAgent + app removed; auto-install disabled). Re-enable: cdt-menubar install-login"
}

case "${1:-install}" in
  build)                 build ;;
  start)                 start ;;
  stop)                  stop ;;
  restart)               stop; start ;;
  status|check|once)     status ;;
  install-login|login)   install_login ;;
  uninstall|remove)      uninstall ;;
  install)               build && install_login && start ;;
  *) echo "usage: cdt-menubar {install|build|start|stop|restart|status|install-login|uninstall}"; exit 1 ;;
esac
