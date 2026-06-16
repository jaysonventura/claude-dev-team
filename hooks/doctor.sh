#!/usr/bin/env bash
# cdt-doctor — health check for the claude-dev-team install. Prints [ok]/[warn]/[FAIL] per component with
# a fix hint for anything not green. Read-only, fail-open.
set +e
CDT_HOME="$HOME/.claude"; BIN="$CDT_HOME/bin"; ENVF="$CDT_HOME/claude-dev-team.env"
ok=0; warn=0; bad=0
P(){ echo "  [ok]   $1"; ok=$((ok+1)); }
W(){ echo "  [warn] $1 — $2"; warn=$((warn+1)); }
F(){ echo "  [FAIL] $1 — $2"; bad=$((bad+1)); }
jval(){ command -v python3 >/dev/null 2>&1 && python3 -c "import json,os;print(json.load(open(os.path.expanduser('~/.claude/settings.json'))).get('$1',''))" 2>/dev/null; }
jenv(){ command -v python3 >/dev/null 2>&1 && python3 -c "import json,os;print((json.load(open(os.path.expanduser('~/.claude/settings.json'))).get('env') or {}).get('$1',''))" 2>/dev/null; }
genv(){ grep -E "^$1=" "$ENVF" 2>/dev/null | cut -d= -f2-; }

echo "claude-dev-team — doctor"

missing=""
for c in cdt-notify cdt-setup cdt-stats cdt-task cdt-tokens cdt-menubar cdt-recall cdt-advise cdt-pr cdt-config cdt-doctor cdt-learn cdt-budget cdt-statusline cdt-deps cdt-worktree cdt-auto cdt-version; do
  [ -x "$BIN/$c" ] || missing="$missing $c"
done
[ -z "$missing" ] && P "CLIs installed" || W "CLIs missing:$missing" "open a new Claude Code session (the SessionStart hook installs them)"

[ -f "$CDT_HOME/claude-dev-team.db" ] && P "state DB present" || W "state DB missing" "it populates as you complete tasks"
command -v python3 >/dev/null 2>&1 && P "python3 available" || F "python3 missing" "required for recall/advise/config — run: cdt-deps --install"

if command -v gh >/dev/null 2>&1; then
  gh auth status >/dev/null 2>&1 && P "gh authenticated (autopilot ready)" || W "gh not authenticated" "gh auth login — only needed for /autopilot"
else W "gh not installed" "optional — only for /autopilot"; fi

# Worktree isolation: cdt-worktree needs git; native `claude --worktree` sessions need a recent CLI.
if command -v git >/dev/null 2>&1; then
  P "git present (cdt-worktree isolation ready)"
  if command -v claude >/dev/null 2>&1 && claude --help 2>/dev/null | grep -q -- '--worktree'; then
    P "claude --worktree supported"
  fi
else W "git not found" "worktree isolation + autopilot need git — run: cdt-deps --install"; fi

# Autonomous orchestration: the mode router + cost governor (cdt-auto). Engines are opt-in.
au="$(genv CDT_AUTONOMY)"; [ -z "$au" ] && au="assist"
tm="$(genv CDT_TEAMS)"; [ -z "$tm" ] && tm="off"
sc="$(genv CDT_SCALE)"; [ -z "$sc" ] && sc="off"
P "autonomy: $au  (teams=$tm · scale=$sc)"
if [ "$tm" = "on" ]; then
  [ "$(jenv CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS)" = "1" ] && P "agent-team flag set (DEPTH ready)" \
    || W "agent-team flag missing" "re-run: cdt-config teams on (sets CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1)"
fi
if [ "$sc" = "on" ]; then
  cv="$(command -v claude >/dev/null 2>&1 && claude --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)"
  if [ -n "$cv" ]; then
    [ "$(printf '%s\n2.1.154\n' "$cv" | sort -V | head -1)" = "2.1.154" ] && P "Claude Code $cv (workflow BREADTH ready)" \
      || W "Claude Code $cv < 2.1.154" "dynamic workflows need 2.1.154+ — update Claude Code"
  else
    W "scale on but Claude Code version unknown" "can't verify the 2.1.154+ requirement for workflows"
  fi
fi

prov="$(grep -E '^CDT_NOTIFY_PROVIDER=' "$ENVF" 2>/dev/null | cut -d= -f2-)"
{ [ -n "$prov" ] && [ "$prov" != "off" ]; } && P "notifier configured ($prov)" || W "notifier not configured" "optional — run: cdt-setup"

en="$(grep -E '^CDT_ENABLED=' "$ENVF" 2>/dev/null | cut -d= -f2-)"
[ "$en" = "0" ] && W "CDT is DISABLED" "re-enable: cdt-config on" || P "CDT enabled"

eff="$(jval effortLevel)"; mdl="$(jval model)"
[ "$eff" = "xhigh" ] && P "effort: xhigh" || W "effort: ${eff:-unset}" "recommended: cdt-config effort xhigh"
case "$mdl" in
  *opus*) P "model: $mdl" ;;
  "")     W "model: unset" "recommended Opus 4.8: cdt-config model claude-opus-4-8" ;;
  *)      W "model: $mdl (not Opus)" "for max quality: cdt-config model claude-opus-4-8" ;;
esac

if [ "$(uname)" = "Darwin" ]; then
  pgrep -f "CDT Usage.app/Contents/MacOS/cdt-menubar" >/dev/null 2>&1 && P "menu bar app running" || W "menu bar not running" "start: cdt-menubar install"
fi

if command -v python3 >/dev/null 2>&1; then
  deps="$(python3 -c "import json,os;d=json.load(open(os.path.expanduser('~/.claude/settings.json'))).get('enabledPlugins',{});print(sum(1 for k in d if any(x in k for x in ['superpowers','code-review','frontend-design','context7'])))" 2>/dev/null)"
  [ "${deps:-0}" -ge 1 ] && P "companion plugins enabled ($deps)" || W "companion plugins not detected" "they auto-install with the plugin (needs Claude Code >= 2.1.143)"
fi

echo
echo "  $ok ok · $warn warn · $bad fail"
exit 0
