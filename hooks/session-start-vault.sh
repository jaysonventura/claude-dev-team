#!/usr/bin/env bash
# SessionStart hook: bootstrap the vault, the SQLite DB, and the stable ~/.claude/bin CLIs,
# then inject accumulated learnings into the session context. Fail-open (always exit 0).
set +e

HOOKS_DIR="$(cd "$(dirname "$0")" 2>/dev/null && pwd)"
CDT_HOME="$HOME/.claude"
VAULT="$CDT_HOME/vault"
BIN="$CDT_HOME/bin"

# 1) Bootstrap the vault from the plugin template (only seeds missing files).
mkdir -p "$VAULT/sessions" "$VAULT/adrs" "$BIN" 2>/dev/null
if [ -d "$HOOKS_DIR/vault-template" ]; then
  for f in README.md learnings.md log.md status-log.md; do
    [ -f "$VAULT/$f" ] || cp "$HOOKS_DIR/vault-template/$f" "$VAULT/$f" 2>/dev/null
  done
fi

# 2) Install/refresh the stable CLIs so the orchestrator and commands have fixed paths.
cp "$HOOKS_DIR/notify.sh" "$BIN/cdt-notify"   2>/dev/null && chmod +x "$BIN/cdt-notify" 2>/dev/null
cp "$HOOKS_DIR/setup.sh"  "$BIN/cdt-setup"    2>/dev/null && chmod +x "$BIN/cdt-setup"  2>/dev/null
cp "$HOOKS_DIR/stats.sh"  "$BIN/cdt-stats"    2>/dev/null && chmod +x "$BIN/cdt-stats"  2>/dev/null
cp "$HOOKS_DIR/task.sh"   "$BIN/cdt-task"     2>/dev/null && chmod +x "$BIN/cdt-task"   2>/dev/null
cp "$HOOKS_DIR/db.sh"     "$BIN/cdt-db.sh"    2>/dev/null
cp "$HOOKS_DIR/menubar-install.sh" "$BIN/cdt-menubar" 2>/dev/null && chmod +x "$BIN/cdt-menubar" 2>/dev/null
cp "$HOOKS_DIR/recall.sh"  "$BIN/cdt-recall"   2>/dev/null && chmod +x "$BIN/cdt-recall"  2>/dev/null
cp "$HOOKS_DIR/advise.sh"  "$BIN/cdt-advise"   2>/dev/null && chmod +x "$BIN/cdt-advise"  2>/dev/null
cp "$HOOKS_DIR/pr.sh"      "$BIN/cdt-pr"       2>/dev/null && chmod +x "$BIN/cdt-pr"      2>/dev/null
cp "$HOOKS_DIR/config.sh"  "$BIN/cdt-config"   2>/dev/null && chmod +x "$BIN/cdt-config"  2>/dev/null
cp "$HOOKS_DIR/doctor.sh"  "$BIN/cdt-doctor"   2>/dev/null && chmod +x "$BIN/cdt-doctor"  2>/dev/null
cp "$HOOKS_DIR/learn.sh"   "$BIN/cdt-learn"    2>/dev/null && chmod +x "$BIN/cdt-learn"   2>/dev/null
cp "$HOOKS_DIR/budget.sh"  "$BIN/cdt-budget"   2>/dev/null && chmod +x "$BIN/cdt-budget"  2>/dev/null
cp "$HOOKS_DIR/statusline.sh" "$BIN/cdt-statusline" 2>/dev/null && chmod +x "$BIN/cdt-statusline" 2>/dev/null

# Stage the menu bar Swift source to a stable, buildable location (source only — not .build).
MENUBAR_SRC="$(cd "$HOOKS_DIR/.." 2>/dev/null && pwd)/menubar"
if [ -f "$MENUBAR_SRC/Package.swift" ]; then
  mkdir -p "$CDT_HOME/claude-dev-team-menubar" 2>/dev/null
  cp "$MENUBAR_SRC/Package.swift" "$CDT_HOME/claude-dev-team-menubar/" 2>/dev/null
  cp -R "$MENUBAR_SRC/Sources" "$CDT_HOME/claude-dev-team-menubar/" 2>/dev/null
  cp "$MENUBAR_SRC/Info.plist" "$CDT_HOME/claude-dev-team-menubar/" 2>/dev/null
  cp "$MENUBAR_SRC/AppIcon.icns" "$CDT_HOME/claude-dev-team-menubar/" 2>/dev/null
fi

# Auto-install the menu bar app on macOS (once, in the background) unless disabled.
if [ "$(uname)" = "Darwin" ] && command -v swift >/dev/null 2>&1; then
  AUTO=1
  [ -f "$CDT_HOME/claude-dev-team.env" ] && . "$CDT_HOME/claude-dev-team.env" 2>/dev/null
  AUTO="${CDT_MENUBAR_AUTO:-$AUTO}"
  # Install once: guard on a success marker the installer writes (not a legacy plist that the
  # SMAppService path never creates) — otherwise every session/clear/compact would kill+relaunch the app.
  if [ "$AUTO" != "0" ] && [ ! -f "$CDT_HOME/.cdt-menubar-disabled" ] && [ ! -f "$CDT_HOME/.cdt-menubar-installed" ] && [ -x "$BIN/cdt-menubar" ]; then
    ( "$BIN/cdt-menubar" install-login >/dev/null 2>&1 ) &
  fi
fi

# 3) Initialize the state DB.
[ -f "$BIN/cdt-db.sh" ] && . "$BIN/cdt-db.sh" 2>/dev/null && db_init 2>/dev/null

# 4) Inject context — but first honor the on/off switch (`cdt-config off` → behave as stock Claude Code).
CDT_ENABLED="$(grep -E '^CDT_ENABLED=' "$CDT_HOME/claude-dev-team.env" 2>/dev/null | head -1 | cut -d= -f2-)"
if [ "$CDT_ENABLED" = "0" ]; then
  echo "## claude-dev-team is DISABLED (cdt-config off) — operate as standard Claude Code; do not run the"
  echo "tech-lead orchestration protocol. Re-enable any time: ~/.claude/bin/cdt-config on"
  exit 0
fi

# Inject only the most RECENT lessons (cheap + scales as the vault grows). For lessons relevant to a
# SPECIFIC task, the orchestrator runs `cdt-recall "<task>"` during triage instead of re-reading the file.
echo "## claude-dev-team — vault learnings (operate as the tech-lead orchestrator)"
if [ -f "$VAULT/learnings.md" ]; then
  grep '^- \[' "$VAULT/learnings.md" 2>/dev/null | tail -n 6
fi
echo
echo "_Triage every task (T0–T3); delegate under contracts; gate; ship; persist. Preferred defaults: **xhigh** effort + **Opus 4.8** (adjust via cdt-config). For lessons relevant to a task, run \`~/.claude/bin/cdt-recall \"<task>\"\`. Report milestones via cdt-notify._"
exit 0
