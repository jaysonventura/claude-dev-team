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

# 3) Load config (may not exist yet — that's fine). Preserve any explicitly-passed overrides
#    (e.g. CDT_NOTIFY_LEVEL=all from `--test`) so sourcing the env file doesn't clobber them.
_LEVEL_OVERRIDE="${CDT_NOTIFY_LEVEL:-}"
_PROVIDER_OVERRIDE="${CDT_NOTIFY_PROVIDER:-}"
[ -f "$ENV_FILE" ] && . "$ENV_FILE" 2>/dev/null
[ -n "$_LEVEL_OVERRIDE" ] && CDT_NOTIFY_LEVEL="$_LEVEL_OVERRIDE"
[ -n "$_PROVIDER_OVERRIDE" ] && CDT_NOTIFY_PROVIDER="$_PROVIDER_OVERRIDE"

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

# The webhook URL / bot token are secrets — pass them via a stdin curl-config (-K -) so they never
# appear in the process argument list (visible to any local user via `ps`/`/proc`).
push_discord() {
  [ -n "$CDT_DISCORD_WEBHOOK_URL" ] || return 0
  local body; body="$(json_escape "$TEXT")"
  printf 'url = "%s"\n' "$CDT_DISCORD_WEBHOOK_URL" | \
    curl -sf -m 10 -K - -H "Content-Type: application/json" \
         -d "{\"content\":\"$body\"}" >/dev/null 2>&1 || true
}

push_telegram() {
  [ -n "$CDT_TELEGRAM_BOT_TOKEN" ] && [ -n "$CDT_TELEGRAM_CHAT_ID" ] || return 0
  printf 'url = "https://api.telegram.org/bot%s/sendMessage"\n' "$CDT_TELEGRAM_BOT_TOKEN" | \
    curl -sf -m 10 -K - \
         --data-urlencode "chat_id=${CDT_TELEGRAM_CHAT_ID}" \
         --data-urlencode "text=${TEXT}" >/dev/null 2>&1 || true
}

case "$PROVIDER" in
  discord) push_discord ;;
  telegram) push_telegram ;;
  both) push_discord; push_telegram ;;
esac

exit 0
