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

# --- Input validation (security) -----------------------------------------------------------------
# Only store values matching the expected shape. The env file is later `source`-d by the hooks, so a
# pasted secret containing $(...), backticks, ';', whitespace, or a NEWLINE must never reach it.
# We use bash `[[ =~ ]]` (anchors the WHOLE string — unlike `grep`, which matches line-by-line and
# would let "0\n<payload>" slip a second env line through), plus an explicit control-char reject.
_safe_oneline() { case "$1" in ''|*[[:cntrl:]]*) return 1 ;; *) return 0 ;; esac; }   # no empty/newline/ctrl
valid_discord()  { _safe_oneline "$1" && [[ "$1" =~ ^https://(discord|discordapp)\.com/api/webhooks/[0-9]+/[A-Za-z0-9_-]+$ ]]; }
valid_tg_token() { _safe_oneline "$1" && [[ "$1" =~ ^[0-9]+:[A-Za-z0-9_-]+$ ]]; }
valid_chat_id()  { _safe_oneline "$1" && [[ "$1" =~ ^-?[0-9]+$ ]]; }
valid_provider() { case "$1" in discord|telegram|both|off) return 0 ;; *) return 1 ;; esac; }
valid_level()    { case "$1" in all|milestones|off) return 0 ;; *) return 1 ;; esac; }

# Set the provider additively: if both channels end up configured, use "both" (don't clobber the other).
set_provider_additive() {
  if [ -n "$(get_var CDT_DISCORD_WEBHOOK_URL)" ] && [ -n "$(get_var CDT_TELEGRAM_BOT_TOKEN)" ]; then
    set_var CDT_NOTIFY_PROVIDER "both"
  else
    set_var CDT_NOTIFY_PROVIDER "$1"
  fi
}

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
  CDT_NOTIFY_LEVEL=all "$n" DELIVERED "claude-dev-team is wired up — this is what milestone alerts look like 🎉" --task "notifier setup" --tier T0 --duration 3
  echo "Test sent (check your channel for the rich message; if nothing arrives, re-check the webhook/token)."
}

# Auto-detect the most recent chat id from the bot's getUpdates (needs the user to have messaged the bot).
fetch_telegram_chat_id() {
  local token="$1" resp
  command -v curl >/dev/null 2>&1 || return 0
  # Pass the secret token via a stdin curl-config (-K -) so it never appears in argv (ps/proc-visible).
  resp="$(printf 'url = "https://api.telegram.org/bot%s/getUpdates"\n' "$token" | curl -sf -m 10 -K - 2>/dev/null)" || return 0
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
  --discord)
    if valid_discord "$2"; then
      set_var CDT_DISCORD_WEBHOOK_URL "$2"; set_provider_additive discord
      echo "Discord webhook saved (provider: $(get_var CDT_NOTIFY_PROVIDER))."
    else
      echo "Invalid Discord webhook URL — expected https://discord.com/api/webhooks/<id>/<token>. Not saved."
    fi
    exit 0 ;;
  --telegram)
    if valid_tg_token "$2"; then
      set_var CDT_TELEGRAM_BOT_TOKEN "$2"
      chat="$3"; [ -z "$chat" ] && chat="$(fetch_telegram_chat_id "$2")"
      if valid_chat_id "$chat"; then
        set_var CDT_TELEGRAM_CHAT_ID "$chat"; set_provider_additive telegram
        echo "Telegram saved (chat id: $chat, provider: $(get_var CDT_NOTIFY_PROVIDER))."
      else
        echo "Token saved, but no valid chat id — message your bot in Telegram, then re-run: cdt-setup --telegram <token>"
      fi
    elif [ -n "$2" ]; then
      echo "Invalid Telegram bot token — expected <digits>:<token>. Not saved."
    fi
    exit 0 ;;
  --provider) if valid_provider "$2"; then set_var CDT_NOTIFY_PROVIDER "$2"; echo "provider=$2"; else echo "Invalid provider (discord|telegram|both|off)."; fi; exit 0 ;;
  --level)    if valid_level "$2"; then set_var CDT_NOTIFY_LEVEL "$2"; echo "level=$2"; else echo "Invalid level (all|milestones|off)."; fi; exit 0 ;;
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
    if valid_discord "$url"; then set_var CDT_DISCORD_WEBHOOK_URL "$url"
    elif [ -n "$url" ]; then echo "  Invalid webhook URL — not saved."; fi ;;
esac
case "$choice" in
  2|3)
    echo "  (First, send any message to your bot in Telegram so it can auto-detect your chat id.)"
    printf "Paste Telegram bot token (hidden): "; read -rs tok; echo
    if valid_tg_token "$tok"; then
      set_var CDT_TELEGRAM_BOT_TOKEN "$tok"
      chat="$(fetch_telegram_chat_id "$tok")"
      if valid_chat_id "$chat"; then
        echo "  Auto-detected chat id: $chat"
      else
        printf "  Could not auto-detect — enter chat id manually: "; read -r chat
      fi
      if valid_chat_id "$chat"; then set_var CDT_TELEGRAM_CHAT_ID "$chat"
      elif [ -n "$chat" ]; then echo "  Invalid chat id (must be a number) — not saved."; fi
    elif [ -n "$tok" ]; then
      echo "  Invalid bot token — not saved."
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
