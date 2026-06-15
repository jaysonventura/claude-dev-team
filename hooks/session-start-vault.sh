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

# 3) Initialize the state DB.
[ -f "$BIN/cdt-db.sh" ] && . "$BIN/cdt-db.sh" 2>/dev/null && db_init 2>/dev/null

# 4) Inject context: recent learnings (kept small to stay token-cheap).
echo "## claude-dev-team — vault learnings (operate as the tech-lead orchestrator)"
if [ -f "$VAULT/learnings.md" ]; then
  head -c 4000 "$VAULT/learnings.md" 2>/dev/null
fi
echo
echo "_Triage every task (T0–T3); delegate under contracts; gate; ship; persist. Report milestones via cdt-notify._"
exit 0
