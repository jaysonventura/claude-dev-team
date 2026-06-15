#!/usr/bin/env bash
# cdt-notify <TYPE> <message...>
#   TYPE in: DELIVERED | DEFERRED | BLOCKER | SHIP | INFO
# Always logs to ~/.claude/vault/status-log.md and the SQLite DB.
# Pushes to Discord/Telegram if configured. Fail-open: never errors out a caller.
set +e

TYPE="${1:-INFO}"; shift 2>/dev/null
MSG="$*"
[ -z "$MSG" ] && MSG="(no message)"

CDT_HOME="$HOME/.claude"
ENV_FILE="$CDT_HOME/claude-dev-team.env"
VAULT="$CDT_HOME/vault"
STATUS_LOG="$VAULT/status-log.md"
TS="$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null)"

# 1) Always document to the vault status log.
mkdir -p "$VAULT" 2>/dev/null
printf -- "- %s  **%s**  %s\n" "$TS" "$TYPE" "$MSG" >> "$STATUS_LOG" 2>/dev/null

# 2) Log to the state DB if the helper is available.
[ -f "$CDT_HOME/bin/cdt-db.sh" ] && . "$CDT_HOME/bin/cdt-db.sh" 2>/dev/null && db_event "$TYPE" "$MSG" "${CLAUDE_SESSION_ID:-}" 2>/dev/null

# 3) Load config (may not exist yet — that's fine).
[ -f "$ENV_FILE" ] && . "$ENV_FILE" 2>/dev/null

PROVIDER="${CDT_NOTIFY_PROVIDER:-off}"
LEVEL="${CDT_NOTIFY_LEVEL:-milestones}"

# Respect verbosity: off = log only; milestones = skip INFO; all = everything.
case "$LEVEL" in
  off) exit 0 ;;
  milestones) [ "$TYPE" = "INFO" ] && exit 0 ;;
esac
[ "$PROVIDER" = "off" ] && exit 0
command -v curl >/dev/null 2>&1 || exit 0

ICON="ℹ️"
case "$TYPE" in
  DELIVERED) ICON="✅" ;; SHIP) ICON="🚀" ;;
  BLOCKER) ICON="⛔" ;; DEFERRED) ICON="⏸️" ;;
esac
TEXT="$ICON [$TYPE] $MSG"

json_escape() { printf '%s' "$1" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g' | tr '\n\r' '  '; }

push_discord() {
  [ -n "$CDT_DISCORD_WEBHOOK_URL" ] || return 0
  local body; body="$(json_escape "$TEXT")"
  curl -sf -m 10 -H "Content-Type: application/json" \
       -d "{\"content\":\"$body\"}" "$CDT_DISCORD_WEBHOOK_URL" >/dev/null 2>&1 || true
}

push_telegram() {
  [ -n "$CDT_TELEGRAM_BOT_TOKEN" ] && [ -n "$CDT_TELEGRAM_CHAT_ID" ] || return 0
  curl -sf -m 10 "https://api.telegram.org/bot${CDT_TELEGRAM_BOT_TOKEN}/sendMessage" \
       --data-urlencode "chat_id=${CDT_TELEGRAM_CHAT_ID}" \
       --data-urlencode "text=${TEXT}" >/dev/null 2>&1 || true
}

case "$PROVIDER" in
  discord) push_discord ;;
  telegram) push_telegram ;;
  both) push_discord; push_telegram ;;
esac

exit 0
