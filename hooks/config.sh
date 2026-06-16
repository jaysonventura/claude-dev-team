#!/usr/bin/env bash
# cdt-config — enable/disable claude-dev-team and set its defaults (effort, model).
#
#   cdt-config                       show current config
#   cdt-config on  | enable          turn the orchestration layer ON
#   cdt-config off | disable         turn it OFF (acts as stock Claude Code next session)
#   cdt-config effort <low|medium|high|xhigh>   set the default effort (default: xhigh)
#   cdt-config model  <opus|sonnet|haiku|claude-opus-4-8|...>   set the default model (default: Opus 4.8)
#   cdt-config reset                 restore defaults: enabled, xhigh, Opus 4.8
#
# enable/disable lives in ~/.claude/claude-dev-team.env (read by the SessionStart hook).
# effort + model are written to ~/.claude/settings.json (Claude Code's real settings; apply next session;
# the write is a safe merge — all other keys preserved). NOTE: effort 'max' is session-only (/effort max)
# and cannot be persisted, by design — the recommended persistent default is xhigh.
set +e

CDT_HOME="$HOME/.claude"
BIN="$CDT_HOME/bin"
ENV_FILE="${CDT_ENV_FILE:-$CDT_HOME/claude-dev-team.env}"
SETTINGS="${CDT_SETTINGS:-$CDT_HOME/settings.json}"
DEFAULT_EFFORT="xhigh"
DEFAULT_MODEL="claude-opus-4-8"   # Opus 4.8
mkdir -p "$CDT_HOME" 2>/dev/null
[ -f "$ENV_FILE" ] || : > "$ENV_FILE"
chmod 600 "$ENV_FILE" 2>/dev/null

set_env() {   # upsert KEY=VALUE (values here are controlled constants — 0/1)
  local key="$1" val="$2" tmp
  tmp="$(mktemp 2>/dev/null || echo "$ENV_FILE.tmp")"
  grep -v -E "^${key}=" "$ENV_FILE" 2>/dev/null > "$tmp"
  printf '%s=%s\n' "$key" "$val" >> "$tmp"
  mv "$tmp" "$ENV_FILE" 2>/dev/null; chmod 600 "$ENV_FILE" 2>/dev/null
}
get_env() { grep -E "^$1=" "$ENV_FILE" 2>/dev/null | head -1 | cut -d= -f2-; }

# Merge one key into settings.json — preserve every other key, write atomically, never corrupt on error.
set_setting() {
  command -v python3 >/dev/null 2>&1 || { echo "cdt-config: python3 required to edit settings.json"; return 1; }
  KEY="$1" VAL="$2" SETTINGS="$SETTINGS" python3 - <<'PY'
import json, os, sys, tempfile
p = os.environ["SETTINGS"]; key = os.environ["KEY"]; val = os.environ["VAL"]
try:
    d = json.load(open(p)) if os.path.exists(p) else {}
except Exception:
    print("cdt-config: settings.json is not valid JSON — not modified"); sys.exit(1)
if not isinstance(d, dict):
    print("cdt-config: settings.json is not an object — not modified"); sys.exit(1)
d[key] = val
d_dir = os.path.dirname(p) or "."
fd, tmp = tempfile.mkstemp(dir=d_dir)
try:
    with os.fdopen(fd, "w") as f:
        json.dump(d, f, indent=2); f.write("\n")
    os.replace(tmp, p)
except Exception as e:
    try: os.unlink(tmp)
    except OSError: pass
    print(f"cdt-config: could not write settings.json ({e})"); sys.exit(1)
print(f"cdt-config: settings.json {key} = {val}  (applies next session — restart Claude Code)")
PY
}
get_setting() {
  command -v python3 >/dev/null 2>&1 || { echo ""; return; }
  KEY="$1" SETTINGS="$SETTINGS" python3 - <<'PY'
import json, os
p = os.environ["SETTINGS"]; key = os.environ["KEY"]
try:
    print(json.load(open(p)).get(key, "") if os.path.exists(p) else "")
except Exception:
    print("")
PY
}

# Merge KEY into settings.json's nested "env" object (empty VAL removes it). Preserves everything else.
# Used to set CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS for the agent-team DEPTH engine.
set_env_setting() {
  command -v python3 >/dev/null 2>&1 || { echo "cdt-config: python3 required to edit settings.json"; return 1; }
  KEY="$1" VAL="$2" SETTINGS="$SETTINGS" python3 - <<'PY'
import json, os, sys, tempfile
p = os.environ["SETTINGS"]; key = os.environ["KEY"]; val = os.environ["VAL"]
try:
    d = json.load(open(p)) if os.path.exists(p) else {}
except Exception:
    print("cdt-config: settings.json is not valid JSON — not modified"); sys.exit(1)
if not isinstance(d, dict):
    print("cdt-config: settings.json is not an object — not modified"); sys.exit(1)
env = d.get("env")
if not isinstance(env, dict): env = {}
if val == "": env.pop(key, None)
else: env[key] = val
d["env"] = env
fd, tmp = tempfile.mkstemp(dir=os.path.dirname(p) or ".")
try:
    with os.fdopen(fd, "w") as f:
        json.dump(d, f, indent=2); f.write("\n")
    os.replace(tmp, p)
except Exception as e:
    try: os.unlink(tmp)
    except OSError: pass
    print(f"cdt-config: could not write settings.json ({e})"); sys.exit(1)
print(f"cdt-config: settings.json env.{key} {'removed' if val=='' else '= '+val}  (applies next session)")
PY
}

statusline_state() {
  command -v python3 >/dev/null 2>&1 || { echo off; return; }
  SETTINGS="$SETTINGS" python3 -c "import json,os;p=os.environ['SETTINGS'];d=json.load(open(p)) if os.path.exists(p) else {};print('on' if 'cdt-statusline' in ((d.get('statusLine') or {}).get('command') or '') else 'off')" 2>/dev/null
}

show() {
  local en eco; en="$(get_env CDT_ENABLED)"; [ -z "$en" ] && en="1"; eco="$(get_env CDT_ECO)"; [ -z "$eco" ] && eco="off"
  local eff mdl; eff="$(get_setting effortLevel)"; mdl="$(get_setting model)"
  local au tm sc; au="$(get_env CDT_AUTONOMY)"; [ -z "$au" ] && au="assist"; tm="$(get_env CDT_TEAMS)"; [ -z "$tm" ] && tm="off"; sc="$(get_env CDT_SCALE)"; [ -z "$sc" ] && sc="off"
  local vg; vg="$(get_env CDT_VERIFY_GATE)"; [ -z "$vg" ] && vg="block"
  local sg; sg="$(get_env CDT_SCOPE_GATE)"; [ -z "$sg" ] && sg="warn"
  local mg; mg="$(get_env CDT_MEMORY_GATE)"; [ -z "$mg" ] && mg="warn"
  echo "claude-dev-team config:"
  echo "  status    : $([ "$en" = "0" ] && echo DISABLED || echo enabled)"
  echo "  effort    : ${eff:-(unset)}   (default $DEFAULT_EFFORT)"
  echo "  model     : ${mdl:-(unset → Claude Code default)}   (recommended $DEFAULT_MODEL = Opus 4.8)"
  echo "  eco       : $eco   (default off; auto = conserve when weekly usage is high; on | off | auto)"
  echo "  verify    : $vg   (block | warn | off — block a Stop with edits but no test/build/lint after them)"
  echo "  scope     : $sg   (warn | block | off — flag a subagent that wrote outside its exclusive contract)"
  echo "  memory    : $mg   (warn | block | off — nudge a team-tier session to persist a vault lesson)"
  echo "  autonomy  : $au   (off | assist | auto — autonomous escalation; details: cdt-auto status)"
  echo "  teams     : $tm   ·  scale : $sc   (DEPTH/BREADTH engines; off by default, opt in to enable)"
  echo "  statusline: $(statusline_state)   (terminal status line)"
  echo "  effort/model apply on the next session (restart Claude Code). Toggle CDT: cdt-config on|off"
}

case "${1:-show}" in
  show|--show|status) show ;;
  on|enable)   set_env CDT_ENABLED 1; echo "claude-dev-team: ENABLED." ;;
  off|disable) set_env CDT_ENABLED 0; echo "claude-dev-team: DISABLED — next session acts as stock Claude Code. Re-enable: cdt-config on" ;;
  effort)
    case "$2" in
      low|medium|high|xhigh) set_setting effortLevel "$2" ;;
      max) echo "cdt-config: 'max' is session-only (use /effort max) and cannot be persisted. Recommended persistent default: xhigh." ;;
      *) echo "cdt-config: effort must be one of: low | medium | high | xhigh" ;;
    esac ;;
  model)
    if [ -z "$2" ]; then
      echo "cdt-config: usage: cdt-config model <opus|sonnet|haiku|claude-opus-4-8|...>"
    elif [[ "$2" =~ ^[A-Za-z0-9._-]+(\[1m\])?$ ]]; then
      set_setting model "$2"
    else
      echo "cdt-config: invalid model string"
    fi ;;
  eco)
    case "$2" in
      on|off|auto) set_env CDT_ECO "$2"; echo "claude-dev-team: eco = $2 (auto conserves when weekly usage is high)." ;;
      *) echo "cdt-config: eco must be one of: on | off | auto" ;;
    esac ;;
  verify)
    case "$2" in
      block|warn|off) set_env CDT_VERIFY_GATE "$2"; echo "claude-dev-team: verify gate = $2  (block = stop a session that edited files but ran no test/build/lint afterward · warn = notice only · off = disabled)." ;;
      *) echo "cdt-config: verify must be one of: block | warn | off" ;;
    esac ;;
  scope)
    case "$2" in
      warn|block|off) set_env CDT_SCOPE_GATE "$2"; echo "claude-dev-team: scope gate = $2  (flag a subagent that wrote files outside its exclusive contract or into a peer's scope; warn = notice · block = stop · off = disabled)." ;;
      *) echo "cdt-config: scope must be one of: warn | block | off" ;;
    esac ;;
  memory)
    case "$2" in
      warn|block|off) set_env CDT_MEMORY_GATE "$2"; echo "claude-dev-team: memory gate = $2  (a team-tier session that edited files but recorded no vault lesson; warn = nudge · block = stop · off = disabled)." ;;
      *) echo "cdt-config: memory must be one of: warn | block | off" ;;
    esac ;;
  autonomy)
    case "$2" in
      off|assist|auto) set_env CDT_AUTONOMY "$2"; echo "claude-dev-team: autonomy = $2  (off = bounded only · assist = auto-teams, ask-before-workflows · auto = self-run both within budget). See: cdt-auto status" ;;
      *) echo "cdt-config: autonomy must be one of: off | assist | auto" ;;
    esac ;;
  teams)
    case "$2" in
      on)  set_env CDT_TEAMS on;  set_env_setting CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS 1
           echo "claude-dev-team: agent-team DEPTH mode ON (experimental flag set; restart Claude Code)." ;;
      off) set_env CDT_TEAMS off; set_env_setting CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS ""
           echo "claude-dev-team: agent-team DEPTH mode OFF." ;;
      *) echo "cdt-config: usage: cdt-config teams on|off" ;;
    esac ;;
  scale)
    case "$2" in
      on|off) set_env CDT_SCALE "$2"; echo "claude-dev-team: dynamic-workflow BREADTH (scale) mode = $2  (needs Claude Code >= 2.1.154)." ;;
      *) echo "cdt-config: usage: cdt-config scale on|off" ;;
    esac ;;
  statusline)
    case "$2" in
      on)
        CMD="$BIN/cdt-statusline" SETTINGS="$SETTINGS" python3 - <<'PY'
import json, os, tempfile
p = os.environ["SETTINGS"]; cmd = os.environ["CMD"]
try: d = json.load(open(p)) if os.path.exists(p) else {}
except Exception: print("cdt-config: settings.json invalid — not modified"); raise SystemExit(1)
d["statusLine"] = {"type": "command", "command": cmd, "padding": 0}
fd, tmp = tempfile.mkstemp(dir=os.path.dirname(p) or ".")
with os.fdopen(fd, "w") as f: json.dump(d, f, indent=2); f.write("\n")
os.replace(tmp, p); print("cdt-config: status line ON (restart Claude Code to see it)")
PY
        ;;
      off)
        SETTINGS="$SETTINGS" python3 - <<'PY'
import json, os, tempfile
p = os.environ["SETTINGS"]
try: d = json.load(open(p)) if os.path.exists(p) else {}
except Exception: raise SystemExit(0)
if "statusLine" in d and "cdt-statusline" in ((d["statusLine"] or {}).get("command") or ""):
    d.pop("statusLine", None)
    fd, tmp = tempfile.mkstemp(dir=os.path.dirname(p) or ".")
    with os.fdopen(fd, "w") as f: json.dump(d, f, indent=2); f.write("\n")
    os.replace(tmp, p)
print("cdt-config: status line OFF")
PY
        ;;
      *) echo "cdt-config: usage: cdt-config statusline on|off" ;;
    esac ;;
  reset)
    set_env CDT_ENABLED 1; set_env CDT_ECO off
    set_env CDT_AUTONOMY assist; set_env CDT_TEAMS off; set_env CDT_SCALE off
    set_env_setting CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS ""
    set_setting effortLevel "$DEFAULT_EFFORT"
    set_setting model "$DEFAULT_MODEL"
    echo "claude-dev-team: reset to defaults (enabled, $DEFAULT_EFFORT, Opus 4.8, eco=off, autonomy=assist, engines off)." ;;
  *) echo "usage: cdt-config {show|on|off|effort <lvl>|model <m>|eco <on|off|auto>|verify <block|warn|off>|scope <warn|block|off>|memory <warn|block|off>|autonomy <off|assist|auto>|teams <on|off>|scale <on|off>|statusline <on|off>|reset}"; exit 0 ;;
esac
exit 0
