#!/usr/bin/env bash
# cdt-setup — configure the claude-dev-team notifier without hand-editing .env.
# Interactive (default) or non-interactive flags. Writes ~/.claude/claude-dev-team.env (chmod 600).
#
#   cdt-setup                         interactive menu (hidden input for secrets)
#   cdt-setup --discord <url>         set Discord webhook + provider
#   cdt-setup --telegram <tok> [id]   set Telegram token (+ chat id; auto-detected if omitted)
#   cdt-setup --provider both|discord|telegram|off
#   cdt-setup --level all|milestones|off
#   cdt-setup --test                  send a test notification
#   cdt-setup --show                  print current config (masked)
set +e

ENV_FILE="$HOME/.claude/claude-dev-team.env"
mkdir -p "$HOME/.claude" 2>/dev/null
[ -f "$ENV_FILE" ] || { : > "$ENV_FILE"; }
chmod 600 "$ENV_FILE" 2>/dev/null
# Seed a sane default verbosity on first touch so --show is never blank.
grep -q '^CDT_NOTIFY_LEVEL=' "$ENV_FILE" 2>/dev/null || printf 'CDT_NOTIFY_LEVEL=milestones\n' >> "$ENV_FILE"

# Upsert KEY=VALUE in the env file.
set_var() {
  local key="$1" val="$2" tmp
  tmp="$(mktemp 2>/dev/null || echo "$ENV_FILE.tmp")"
  grep -v -E "^${key}=" "$ENV_FILE" 2>/dev/null > "$tmp"
  printf '%s=%s\n' "$key" "$val" >> "$tmp"
  mv "$tmp" "$ENV_FILE" 2>/dev/null
  chmod 600 "$ENV_FILE" 2>/dev/null
}

get_var() { grep -E "^$1=" "$ENV_FILE" 2>/dev/null | head -1 | cut -d= -f2-; }
mask() { local v="$1"; [ -z "$v" ] && { echo "(unset)"; return; }; echo "${v:0:6}…${v: -4}"; }

show() {
  echo "claude-dev-team notifier config ($ENV_FILE):"
  echo "  provider : $(get_var CDT_NOTIFY_PROVIDER)"
  echo "  level    : $(get_var CDT_NOTIFY_LEVEL)"
  echo "  discord  : $(mask "$(get_var CDT_DISCORD_WEBHOOK_URL)")"
  echo "  telegram : token=$(mask "$(get_var CDT_TELEGRAM_BOT_TOKEN)") chat=$(get_var CDT_TELEGRAM_CHAT_ID)"
}

send_test() {
  local n="$HOME/.claude/bin/cdt-notify"
  [ -x "$n" ] || n="$(cd "$(dirname "$0")" && pwd)/notify.sh"
  CDT_NOTIFY_LEVEL=all "$n" INFO "claude-dev-team test notification — you're wired up. 🎉"
  echo "Test sent (check your channel; if nothing arrives, re-check the webhook/token)."
}

# Auto-detect the most recent chat id from the bot's getUpdates (needs the user to have messaged the bot).
fetch_telegram_chat_id() {
  local token="$1" resp
  command -v curl >/dev/null 2>&1 || return 0
  resp="$(curl -sf -m 10 "https://api.telegram.org/bot${token}/getUpdates" 2>/dev/null)" || return 0
  if command -v python3 >/dev/null 2>&1; then
    printf '%s' "$resp" | python3 -c "import sys,json
try:
    d=json.load(sys.stdin); ids=[]
    for u in d.get('result',[]):
        m=u.get('message') or u.get('edited_message') or u.get('channel_post') or {}
        cid=(m.get('chat') or {}).get('id')
        if cid is not None: ids.append(cid)
    print(ids[-1] if ids else '')
except Exception:
    print('')" 2>/dev/null
  else
    printf '%s' "$resp" | grep -o '\"chat\":{\"id\":[-0-9]*' | tail -1 | grep -o '[-0-9]*$'
  fi
}

case "$1" in
  --discord)  [ -n "$2" ] && { set_var CDT_DISCORD_WEBHOOK_URL "$2"; set_var CDT_NOTIFY_PROVIDER "discord"; echo "Discord webhook saved."; }; exit 0 ;;
  --telegram)
    if [ -n "$2" ]; then
      set_var CDT_TELEGRAM_BOT_TOKEN "$2"
      chat="$3"; [ -z "$chat" ] && chat="$(fetch_telegram_chat_id "$2")"
      if [ -n "$chat" ]; then
        set_var CDT_TELEGRAM_CHAT_ID "$chat"; set_var CDT_NOTIFY_PROVIDER "telegram"
        echo "Telegram saved (chat id: $chat)."
      else
        echo "Token saved, but no chat id found — message your bot in Telegram, then re-run: cdt-setup --telegram <token>"
      fi
    fi
    exit 0 ;;
  --provider) [ -n "$2" ] && { set_var CDT_NOTIFY_PROVIDER "$2"; echo "provider=$2"; }; exit 0 ;;
  --level)    [ -n "$2" ] && { set_var CDT_NOTIFY_LEVEL "$2"; echo "level=$2"; }; exit 0 ;;
  --test)     send_test; exit 0 ;;
  --show)     show; exit 0 ;;
esac

# Interactive
echo "=== claude-dev-team notifier setup ==="
echo "1) Discord   2) Telegram   3) Both   4) Off"
printf "Choose [1-4]: "; read -r choice

case "$choice" in
  1|3)
    printf "Paste Discord webhook URL: "; read -r url
    [ -n "$url" ] && set_var CDT_DISCORD_WEBHOOK_URL "$url" ;;
esac
case "$choice" in
  2|3)
    echo "  (First, send any message to your bot in Telegram so it can auto-detect your chat id.)"
    printf "Paste Telegram bot token (hidden): "; read -rs tok; echo
    if [ -n "$tok" ]; then
      set_var CDT_TELEGRAM_BOT_TOKEN "$tok"
      chat="$(fetch_telegram_chat_id "$tok")"
      if [ -n "$chat" ]; then
        echo "  Auto-detected chat id: $chat"
      else
        printf "  Could not auto-detect — enter chat id manually: "; read -r chat
      fi
      [ -n "$chat" ] && set_var CDT_TELEGRAM_CHAT_ID "$chat"
    fi ;;
esac
case "$choice" in
  1) set_var CDT_NOTIFY_PROVIDER "discord" ;;
  2) set_var CDT_NOTIFY_PROVIDER "telegram" ;;
  3) set_var CDT_NOTIFY_PROVIDER "both" ;;
  *) set_var CDT_NOTIFY_PROVIDER "off" ;;
esac

echo; show
printf "\nSend a test notification now? [y/N]: "; read -r yn
case "$yn" in y|Y) send_test ;; esac
echo "Done. Re-run anytime with: cdt-setup"
