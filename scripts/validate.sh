#!/usr/bin/env bash
# Validate the claude-dev-team plugin: JSON manifests, agent/skill/command frontmatter, shell scripts.
# Used by CI and runnable locally: bash scripts/validate.sh
set -u
cd "$(dirname "$0")/.." || exit 1
fail=0
err(){ echo "  FAIL: $*"; fail=1; }
ok(){ echo "  ok:   $*"; }

echo "== JSON manifests =="
for f in .claude-plugin/plugin.json .claude-plugin/marketplace.json hooks/hooks.json; do
  python3 -m json.tool "$f" >/dev/null 2>&1 && ok "$f" || err "$f does not parse"
done

echo "== hooks.json command paths exist + executable =="
if ! python3 - <<'PY'
import json, os, re, sys
d = json.load(open("hooks/hooks.json"))
bad = 0
for event, groups in (d.get("hooks") or {}).items():
    for g in groups:
        for h in (g.get("hooks") or []):
            cmd = h.get("command", "")
            m = re.search(r'\$\{CLAUDE_PLUGIN_ROOT\}/([^"\']+)', cmd)
            if not m:
                continue
            p = m.group(1)
            if not os.path.isfile(p):
                print(f"  FAIL: {event}: hook file missing: {p}"); bad = 1
            elif not os.access(p, os.X_OK):
                print(f"  FAIL: {event}: hook not executable: {p}"); bad = 1
            else:
                print(f"  ok:   {event} -> {p}")
sys.exit(1 if bad else 0)
PY
then fail=1; fi

has_fm(){ head -12 "$1" | grep -q "^$2:"; }

echo "== Agents (need name + description) =="
for f in agents/*.md; do
  if has_fm "$f" name && has_fm "$f" description; then ok "$(basename "$f")"; else err "$f missing name/description"; fi
done

echo "== Skills (need name + description) =="
for f in skills/*/SKILL.md; do
  if has_fm "$f" name && has_fm "$f" description; then ok "$f"; else err "$f missing name/description"; fi
done

echo "== Commands (need description) =="
for f in commands/*.md; do
  if has_fm "$f" description; then ok "$(basename "$f")"; else err "$f missing description"; fi
done

echo "== Shell scripts =="
if command -v shellcheck >/dev/null 2>&1; then
  # SC1090/SC1091: scripts source runtime files (env, ~/.claude/bin helpers) shellcheck can't follow — not bugs.
  for f in hooks/*.sh scripts/*.sh; do
    if shellcheck -S warning -e SC1090,SC1091 "$f" >/dev/null 2>&1; then ok "$(basename "$f")"; else err "shellcheck: $f"; shellcheck -S warning -e SC1090,SC1091 "$f" | head -15; fi
  done
elif [ -n "${CI:-}" ]; then
  err "shellcheck is required in CI but not installed"
else
  echo "  skip: shellcheck not installed (local)"
fi

echo "== plugin.json <-> marketplace.json version/name sanity =="
if ! python3 - <<'PY'
import json,sys
p=json.load(open('.claude-plugin/plugin.json'))
m=json.load(open('.claude-plugin/marketplace.json'))
errs=[]
if p.get('name')!='cdt': errs.append('plugin name')
names=[x.get('name') for x in m.get('plugins',[])]
if 'cdt' not in names: errs.append('marketplace missing plugin entry')
for e in errs: print('  FAIL:', e)
sys.exit(1 if errs else 0)
PY
then fail=1; fi

echo "== status-line agent tracker (cdt_emoji + running_agents) =="
if ! python3 - <<'PY'
import os, sys, tempfile
sys.path.insert(0, "hooks")
import importlib
ce = importlib.import_module("cdt_emoji")
ra = importlib.import_module("running_agents")
errs = []
# emoji map: auto-mode agents resolve, unknown falls back to robot
if ce.emoji("Explore") != "🔭": errs.append("Explore emoji")
if ce.emoji("claude-dev-team:qa-engineer") != "🧪": errs.append("namespaced role emoji")
if ce.emoji("totally-unknown") != "🤖": errs.append("unknown fallback")
# running set: add/remove/render in an isolated workspace
ws = tempfile.mkdtemp()
if ra.render(ws) != "": errs.append("empty render")
ra.add(ws, "Explore"); ra.add(ws, "Explore"); ra.add(ws, "backend-engineer")
seg = ra.render(ws)
if "Explore×2" not in seg or "backend-engineer×1" not in seg: errs.append("render counts: " + seg)
ra.remove(ws, "Explore")
if "Explore×1" not in ra.render(ws): errs.append("remove one")
ra.remove(ws, "Explore"); ra.remove(ws, "backend-engineer")
if ra.render(ws) != "": errs.append("render empty after removeall")
for e in errs: print("  FAIL:", e)
sys.exit(1 if errs else 0)
PY
then fail=1; else echo "  ok:   emoji map + running-agents add/remove/render"; fi

echo
if [ "$fail" = 0 ]; then echo "ALL CHECKS PASSED"; else echo "VALIDATION FAILED"; exit 1; fi
