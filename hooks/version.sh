#!/usr/bin/env bash
# cdt-version — print the installed claude-dev-team version (plugin + menu bar app).
#
#   cdt-version            human-readable: plugin version, and the menu bar app version if installed
#   cdt-version --short    just the plugin version string (e.g. 1.22.0) — for scripts
#
# The version is read from the plugin's .claude-plugin/plugin.json — preferring the running plugin
# root (CLAUDE_PLUGIN_ROOT, set in hook/command contexts) and otherwise the newest cached install.
set +e

CDT_HOME="$HOME/.claude"

read_version() {   # $1 = path to plugin.json
  [ -f "$1" ] || return 1
  if command -v python3 >/dev/null 2>&1; then
    python3 -c "import json,sys;print(json.load(open(sys.argv[1])).get('version',''))" "$1" 2>/dev/null
  else
    # Fallback parse — first "version": "x.y.z" in the file.
    grep -E '"version"[[:space:]]*:' "$1" | head -1 | sed -E 's/.*"version"[[:space:]]*:[[:space:]]*"([^"]+)".*/\1/'
  fi
}

plugin_version() {
  local pj=""
  if [ -n "${CLAUDE_PLUGIN_ROOT:-}" ] && [ -f "$CLAUDE_PLUGIN_ROOT/.claude-plugin/plugin.json" ]; then
    pj="$CLAUDE_PLUGIN_ROOT/.claude-plugin/plugin.json"
  else
    pj=$(ls -d "$CDT_HOME"/plugins/cache/claude-dev-team/cdt/*/.claude-plugin/plugin.json 2>/dev/null | sort -V | tail -1)
  fi
  read_version "$pj"
}

# Menu bar app version — baked into Info.plist's CFBundleShortVersionString at build time (macOS only).
menubar_version() {
  command -v /usr/libexec/PlistBuddy >/dev/null 2>&1 || return 0
  local apps plist
  for apps in "${CDT_MENUBAR_APPS:-}" "/Applications" "$HOME/Applications"; do
    [ -n "$apps" ] || continue
    plist="$apps/CDT Usage.app/Contents/Info.plist"
    if [ -f "$plist" ]; then
      /usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$plist" 2>/dev/null && return 0
    fi
  done
}

PV="$(plugin_version)"; [ -z "$PV" ] && PV="unknown"

if [ "${1:-}" = "--short" ]; then
  echo "$PV"
  exit 0
fi

echo "claude-dev-team v$PV"
MV="$(menubar_version)"
if [ -n "$MV" ]; then
  if [ "$MV" = "$PV" ]; then
    echo "menu bar app   v$MV  (in sync)"
  else
    echo "menu bar app   v$MV  (stale — rebuild to match: cdt-menubar build)"
  fi
fi
exit 0
