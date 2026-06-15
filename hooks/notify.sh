#!/usr/bin/env bash
# cdt-notify <TYPE> "<message>" [--task "<name>"] [--tier <T0-T3>] [--duration <sec|text>] [--iters <n>] [--tokens <n>]
#   TYPE in: DELIVERED | DEFERRED | BLOCKER | SHIP | INFO
# Logs to ~/.claude/vault/status-log.md + the SQLite DB, and pushes an elegant, detailed message to
# Discord (rich embed) and/or Telegram (formatted HTML). Fail-open: never errors out a caller.
# Secrets go to curl via a stdin config (-K -) so they never appear in argv. All fields are escaped.
set +e

TYPE="${1:-INFO}"; shift 2>/dev/null
MSG=""; TASK=""; TIER=""; DURATION=""; ITERS=""; TOKENS=""
while [ $# -gt 0 ]; do
  case "$1" in
    --task)               shift; TASK="${1:-}" ;;
    --tier)               shift; TIER="${1:-}" ;;
    --duration)           shift; DURATION="${1:-}" ;;
    --iters|--iterations) shift; ITERS="${1:-}" ;;
    --tokens)             shift; TOKENS="${1:-}" ;;
    *)                    MSG="$MSG $1" ;;
  esac
  shift
done
MSG="${MSG# }"; [ -z "$MSG" ] && MSG="(no message)"

CDT_HOME="$HOME/.claude"
ENV_FILE="$CDT_HOME/claude-dev-team.env"
VAULT="$CDT_HOME/vault"
STATUS_LOG="$VAULT/status-log.md"
TS="$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null)"

# Humanize a duration given in whole seconds; pass non-numeric text through unchanged.
fmt_duration() {
  case "$1" in ''|*[!0-9]*) printf '%s' "$1"; return ;; esac
  local s="$1" m
  m=$((s / 60)); s=$((s % 60))
  if [ "$m" -gt 0 ]; then printf '%dm %ds' "$m" "$s"; else printf '%ds' "$s"; fi
}
DURATION="$(fmt_duration "$DURATION")"

# Humanize a token count (45200 -> "45.2k", 3600000 -> "3.6M") — this is what THIS task consumed.
fmt_tokens() {
  case "$1" in ''|*[!0-9]*) printf '%s' "$1"; return ;; esac
  local n="$1"
  if [ "$n" -ge 1000000 ]; then printf '%d.%dM' "$((n/1000000))" "$(((n%1000000)/100000))"
  elif [ "$n" -ge 1000 ]; then printf '%d.%dk' "$((n/1000))" "$(((n%1000)/100))"
  else printf '%d' "$n"; fi
}
[ -n "$TOKENS" ] && TOKENS="$(fmt_tokens "$TOKENS") tokens"

# 1) Vault status log (always) — with a compact detail suffix.
mkdir -p "$VAULT" 2>/dev/null
SUFFIX=""
[ -n "$TASK" ] && SUFFIX="$SUFFIX · $TASK"
[ -n "$TIER" ] && SUFFIX="$SUFFIX · $TIER"
[ -n "$DURATION" ] && SUFFIX="$SUFFIX · $DURATION"
[ -n "$TOKENS" ] && SUFFIX="$SUFFIX · $TOKENS"
printf -- "- %s  **%s**  %s%s\n" "$TS" "$TYPE" "$MSG" "$SUFFIX" >> "$STATUS_LOG" 2>/dev/null

# 2) State DB event.
[ -f "$CDT_HOME/bin/cdt-db.sh" ] && . "$CDT_HOME/bin/cdt-db.sh" 2>/dev/null && db_event "$TYPE" "$MSG" "${CLAUDE_SESSION_ID:-}" 2>/dev/null

# 3) Config — parse only the known keys instead of `source`-ing the file, so a crafted value in a
#    hand-edited env file can never execute (the env format is unquoted KEY=VALUE, written by cdt-setup).
#    Preserve explicit overrides (e.g. CDT_NOTIFY_LEVEL=all from --test) captured before the file is read.
_env_get() { grep -E "^$1=" "$ENV_FILE" 2>/dev/null | head -1 | cut -d= -f2-; }
_LEVEL_OVERRIDE="${CDT_NOTIFY_LEVEL:-}"; _PROVIDER_OVERRIDE="${CDT_NOTIFY_PROVIDER:-}"
if [ -f "$ENV_FILE" ]; then
  CDT_NOTIFY_PROVIDER="$(_env_get CDT_NOTIFY_PROVIDER)"
  CDT_NOTIFY_LEVEL="$(_env_get CDT_NOTIFY_LEVEL)"
  CDT_DISCORD_WEBHOOK_URL="$(_env_get CDT_DISCORD_WEBHOOK_URL)"
  CDT_TELEGRAM_BOT_TOKEN="$(_env_get CDT_TELEGRAM_BOT_TOKEN)"
  CDT_TELEGRAM_CHAT_ID="$(_env_get CDT_TELEGRAM_CHAT_ID)"
fi
[ -n "$_LEVEL_OVERRIDE" ] && CDT_NOTIFY_LEVEL="$_LEVEL_OVERRIDE"
[ -n "$_PROVIDER_OVERRIDE" ] && CDT_NOTIFY_PROVIDER="$_PROVIDER_OVERRIDE"
PROVIDER="${CDT_NOTIFY_PROVIDER:-off}"; LEVEL="${CDT_NOTIFY_LEVEL:-milestones}"

case "$LEVEL" in
  off) exit 0 ;;
  milestones) [ "$TYPE" = "INFO" ] && exit 0 ;;
esac
[ "$PROVIDER" = "off" ] && exit 0
command -v curl >/dev/null 2>&1 || exit 0

ICON="ℹ️"
case "$TYPE" in
  DELIVERED) ICON="✅" ;; SHIP) ICON="🚀" ;; BLOCKER) ICON="⛔" ;; DEFERRED) ICON="⏸️" ;;
esac
export _T="$TYPE" _M="$MSG" _TASK="$TASK" _TIER="$TIER" _DUR="$DURATION" _ITERS="$ITERS" _TOKENS="$TOKENS" _ICON="$ICON" _TS="$TS"

json_escape() { printf '%s' "$1" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g' | tr '\n\r' '  '; }

# Reject a secret that contains characters which could break out of the curl `-K -` config line
# (a stray quote, backslash, or control char). A valid webhook URL / bot token never contains these.
_safe_curl_value() { case "$1" in ''|*[[:cntrl:]]*|*'"'*|*'\'*) return 1 ;; *) return 0 ;; esac; }

discord_payload() {
  python3 -c '
import os, json
t = os.environ.get("_T","INFO"); icon = os.environ.get("_ICON","")
colors = {"DELIVERED":3066993,"SHIP":8146925,"BLOCKER":15158332,"DEFERRED":15105570,"INFO":9807270}
fields = []
def add(n, key, inline=True):
    v = os.environ.get(key,"").strip()
    if v: fields.append({"name": n, "value": v[:1000], "inline": inline})
add("Task","_TASK"); add("Tier","_TIER"); add("Duration","_DUR")
add("Iterations","_ITERS"); add("Tokens (this task)","_TOKENS", inline=False)
embed = {"title": f"{icon} {t}".strip(), "description": os.environ.get("_M","")[:4000],
         "color": colors.get(t,9807270), "fields": fields,
         "footer": {"text":"claude-dev-team"}, "timestamp": os.environ.get("_TS","")}
print(json.dumps({"embeds":[embed]}))'
}

telegram_text() {
  python3 -c '
import os, html
t = os.environ.get("_T","INFO"); icon = os.environ.get("_ICON","")
out = [f"<b>{icon} {html.escape(t)}</b>"]
task = os.environ.get("_TASK","").strip()
if task: out.append(f"<b>{html.escape(task)}</b>")
out.append(html.escape(os.environ.get("_M","")))
det = []
for label, key in [("Tier","_TIER"),("Duration","_DUR"),("Iterations","_ITERS"),("Tokens (this task)","_TOKENS")]:
    v = os.environ.get(key,"").strip()
    if v: det.append(f"• {label}: <b>{html.escape(v)}</b>")
if det: out.append("\n".join(det))
print("\n".join(out))'
}

push_discord() {
  [ -n "$CDT_DISCORD_WEBHOOK_URL" ] || return 0
  _safe_curl_value "$CDT_DISCORD_WEBHOOK_URL" || return 0
  local payload
  if command -v python3 >/dev/null 2>&1; then payload="$(discord_payload)"
  else payload="{\"content\":\"$(json_escape "$ICON [$TYPE] $MSG")\"}"; fi
  printf 'url = "%s"\n' "$CDT_DISCORD_WEBHOOK_URL" | \
    curl -sf -m 10 -K - -H "Content-Type: application/json" --data-raw "$payload" >/dev/null 2>&1 || true
}

push_telegram() {
  [ -n "$CDT_TELEGRAM_BOT_TOKEN" ] && [ -n "$CDT_TELEGRAM_CHAT_ID" ] || return 0
  _safe_curl_value "$CDT_TELEGRAM_BOT_TOKEN" || return 0
  if command -v python3 >/dev/null 2>&1; then
    printf 'url = "https://api.telegram.org/bot%s/sendMessage"\n' "$CDT_TELEGRAM_BOT_TOKEN" | \
      curl -sf -m 10 -K - --data-urlencode "chat_id=${CDT_TELEGRAM_CHAT_ID}" \
           --data-urlencode "text=$(telegram_text)" --data "parse_mode=HTML" >/dev/null 2>&1 || true
  else
    printf 'url = "https://api.telegram.org/bot%s/sendMessage"\n' "$CDT_TELEGRAM_BOT_TOKEN" | \
      curl -sf -m 10 -K - --data-urlencode "chat_id=${CDT_TELEGRAM_CHAT_ID}" \
           --data-urlencode "text=$ICON [$TYPE] $MSG" >/dev/null 2>&1 || true
  fi
}

case "$PROVIDER" in
  discord) push_discord ;;
  telegram) push_telegram ;;
  both) push_discord; push_telegram ;;
esac
exit 0
