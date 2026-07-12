#!/usr/bin/env bash
# cdt-plugin-route "<task>" [--json] — ADVISORY plugin/skill router.
#
# Like cdt-advise / cdt-route: transparent, overridable GUIDANCE — it NEVER blocks and is fully fail-open.
# Deterministic precedence it prints as guidance (the orchestrator still decides):
#   CDT orchestrator → task classification → CDT specialist agent → plugin/skill (advisory) → validation → cdt-verify
# Sources the plugins library (plib_detect_signals) when present, unions with its own shallow repo detection,
# then matches the shipped registry activationRules to suggest plugins/skills WITH a one-line reason each.
# Plugins never front-run a CDT agent: any registry `conflicts` entry => CDT wins (the plugin is deferred).
# Superpowers is gated by CDT_SUPERPOWERS_MODE. Never prints secrets. Pure stdlib python3; fail-open.
set +e

# --- arg parse: a task string + optional --json (order-independent) ---
JSON=0; TASK=""
for a in "$@"; do
  case "$a" in
    --json) JSON=1 ;;
    *) TASK="${TASK:+$TASK }$a" ;;
  esac
done

lc() { printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | sed 's/^[[:space:]]*//; s/[[:space:]]*$//'; }

SELF_DIR="$(cd "$(dirname "$0")" 2>/dev/null && pwd)"
CDT_HOME="$HOME/.claude"

# --- source the plugins library up front for its config resolver (plib_cfg) + plib_detect_signals -----
# The master switches below MUST see cdt-config toggles persisted to the env file, not just process env.
for lib in "$CDT_HOME/bin/cdt-plugins-lib.sh" "$SELF_DIR/plugins-lib.sh" "$SELF_DIR/cdt-plugins-lib.sh"; do
  if [ -f "$lib" ]; then
    # shellcheck disable=SC1090
    . "$lib" 2>/dev/null
    break
  fi
done

# Fallback resolver when the library is absent: process env wins (SET, non-empty), else the value persisted
# in the CDT env file, else the default — mirrors statusline.sh/budget.sh reading the env file directly.
if ! command -v plib_cfg >/dev/null 2>&1; then
  plib_cfg() {
    local var="${1:-}" def="${2:-}" val ef
    [ -n "$var" ] || { printf '%s\n' "$def"; return 0; }
    val="${!var-}"
    [ -n "$val" ] && { printf '%s\n' "$val"; return 0; }
    ef="${CDT_ENV_FILE:-$CDT_HOME/claude-dev-team.env}"
    val="$(grep -E "^${var}=" "$ef" 2>/dev/null | head -1 | cut -d= -f2-)"
    [ -n "$val" ] && { printf '%s\n' "$val"; return 0; }
    printf '%s\n' "$def"
  }
fi

# --- master switches (advisory router respects both; off => print nothing) ---
case "$(lc "$(plib_cfg CDT_PLUGINS_ENABLED 1)")"    in 0|off|false|no) exit 0 ;; esac
case "$(lc "$(plib_cfg CDT_PLUGIN_AUTO_ROUTE 1)")"  in 0|off|false|no) exit 0 ;; esac
SP_MODE="$(lc "$(plib_cfg CDT_SUPERPOWERS_MODE selective)")"
case "$SP_MODE" in off|manual|selective|always) ;; *) SP_MODE="selective" ;; esac

[ "$#" -eq 0 ] && { echo "usage: cdt-plugin-route \"<task description>\" [--json]"; exit 0; }

# --- locate the registry (installed copy first, then the repo default) and the per-plugin overlay state ---
REGISTRY=""
for c in "$CDT_HOME/.cdt/plugins-registry.json" "$SELF_DIR/../config/plugins.json" "$SELF_DIR/plugins.json"; do
  [ -f "$c" ] && { REGISTRY="$c"; break; }
done
STATE="$CDT_HOME/.cdt/plugins-state.json"

# --- gather repo signals: honor plib_detect_signals when the library is installed (fail-open) ---
SIGNALS=""
if command -v plib_detect_signals >/dev/null 2>&1; then
  SIGNALS="$(plib_detect_signals "$PWD" 2>/dev/null)"
fi

# Shallow, dependency-free detection so the router is correct even before the library exists. Unioned with
# whatever plib_detect_signals returned above. Only inspects the top level — enough for advisory hints.
_detect() {
  local d="$PWD" t=""
  if [ -f "$d/package.json" ]; then
    t="$t package.json"
    grep -Eq '"(react|react-dom|next)"[[:space:]]*:' "$d/package.json" 2>/dev/null && t="$t react"
    grep -Eq '"vite"[[:space:]]*:' "$d/package.json" 2>/dev/null && t="$t vite"
    grep -Eq '"typescript"[[:space:]]*:' "$d/package.json" 2>/dev/null && t="$t typescript"
  fi
  [ -f "$d/tsconfig.json" ] && t="$t typescript"
  ls "$d"/*.ts "$d"/*.tsx >/dev/null 2>&1 && t="$t typescript"
  [ -f "$d/composer.json" ] && t="$t composer.json"
  [ -f "$d/artisan" ] && t="$t artisan"
  ls "$d"/*.php >/dev/null 2>&1 && t="$t php"
  ls "$d"/*.tf >/dev/null 2>&1 && t="$t terraform"
  ls "$d"/*.tfvars >/dev/null 2>&1 && t="$t terraform"
  [ -f "$d/Package.swift" ] && t="$t swift"
  ls "$d"/*.swift >/dev/null 2>&1 && t="$t swift"
  ls "$d"/playwright.config.* >/dev/null 2>&1 && t="$t playwright"
  [ -d "$d/e2e" ] && t="$t playwright"
  [ -d "$d/.github" ] && t="$t github_repo"
  printf '%s' "$t"
}
SIGNALS="$SIGNALS $(_detect)"

command -v python3 >/dev/null 2>&1 || exit 0

TASK="$TASK" SIGNALS="$SIGNALS" SP_MODE="$SP_MODE" JSON="$JSON" REGISTRY="$REGISTRY" STATE="$STATE" python3 - <<'PY'
import os, re, json, sys

task    = " " + os.environ.get("TASK", "").lower().strip() + " "
signals = set(os.environ.get("SIGNALS", "").lower().split())
sp_mode = os.environ.get("SP_MODE", "selective")
as_json = os.environ.get("JSON", "0") == "1"

def _load(p):
    try:
        with open(p) as f: return json.load(f)
    except Exception:
        return None

reg = _load(os.environ.get("REGISTRY", "")) if os.environ.get("REGISTRY") else None
entries = {}
if isinstance(reg, dict):
    for p in reg.get("plugins", []) or []:
        if isinstance(p, dict) and p.get("id"):
            entries[p["id"]] = p

FALLBACK_CONFLICTS = {
    "code-review": ["cdt-code-reviewer"],
    "superpowers": ["cdt-planning", "cdt-review", "cdt-tdd"],
}
def conflicts(pid):
    e = entries.get(pid)
    if e is not None:
        return [str(x) for x in (e.get("conflicts") or [])]
    return FALLBACK_CONFLICTS.get(pid, [])

def kws(pid):
    ar = (entries.get(pid, {}) or {}).get("activationRules", {}) or {}
    return [str(k).lower() for k in (ar.get("taskKeywords") or [])]

# per-plugin overlay state: disabled plugins are never recommended. Tolerant of several shapes.
disabled = set()
st = _load(os.environ.get("STATE", "")) if os.environ.get("STATE") else None
def _mark(pid, val):
    if isinstance(val, dict):
        if val.get("enabled") is False or val.get("disabled") is True or str(val.get("state","")).lower() == "disabled":
            disabled.add(pid)
    elif val is False:
        disabled.add(pid)
if isinstance(st, dict):
    node = st.get("plugins") if isinstance(st.get("plugins"), dict) else st
    if isinstance(node, dict):
        for k, v in node.items():
            _mark(k, v)
    for k in (st.get("disabled") or []):
        if isinstance(k, str): disabled.add(k)

def hit(term):
    return re.search(r"(?<![a-z0-9])" + re.escape(term) + r"(?![a-z0-9])", task) is not None
def first_kw(pid):
    for k in kws(pid):
        if hit(k): return k
    return None
def has_sub(words): return any(w in task for w in words)
def has_word(words): return any(hit(w) for w in words)   # word-boundary (so "review" != "preview")

# complexity/risk (mirrors cdt-route) + the CDT-owned areas superpowers must never front-run.
RISK = ["auth","login","password","oauth","token","payment","billing","stripe","secret","credential",
        "crypto","encrypt","infra","terraform","kubernetes","migration","rbac","permission","security",
        "vulnerab","injection"," xss","csrf"]
HARD = ["architect","design ","redesign","refactor","ambiguous","tricky","complex","concurrency",
        "race condition","deadlock","distributed","algorithm","optimi","performance","root cause",
        "debug","review","audit","tradeoff","decide","strategy","api design","data model"]
CDT_OWNED = ["brainstorm","roadmap","planning"," plan ","plan the","write a plan","review","audit",
             "code review","tdd","test-driven","test driven","write tests","failing test","unit test"]
high_complexity = has_sub(RISK) or has_sub(HARD)
cdt_owned       = has_word(CDT_OWNED)   # standalone-word match: "review the code" yes, "preview" no

recs = []       # (id, reason, advisory)
deferred = []   # (id, [conflicting cdt agents])

def consider(pid, reason, advisory=False):
    """Recommend pid, unless disabled (skip) or it conflicts with a CDT agent (defer — CDT wins)."""
    if pid in disabled:
        return False
    cf = conflicts(pid)
    if cf:
        deferred.append((pid, cf))
        return False
    recs.append((pid, reason, advisory))
    return True

# 1) frontend-design (+ typescript-lsp when TS is present)
fd = None
if "react" in signals or "vite" in signals:
    fd = "package.json declares react/vite" if "package.json" in signals else "task targets a react/vite UI"
elif hit("react") or hit("vite"):
    fd = "task targets a react/vite UI"
else:
    k = first_kw("frontend-design")
    if k: fd = "task mentions '%s'" % k
if fd and consider("frontend-design", fd):
    if "typescript" in signals or hit("typescript") or hit("ts") or hit("tsx") or ".ts" in task:
        consider("typescript-lsp", "TypeScript present — LSP for type-accurate edits")

# 2) laravel-boost (+ php-lsp)
lb = None
if "artisan" in signals:
    lb = "artisan + composer.json present" if "composer.json" in signals else "Laravel artisan present"
elif "composer.json" in signals and (hit("laravel") or hit("artisan") or hit("eloquent") or hit("blade")):
    lb = "composer.json + a Laravel task"
else:
    k = first_kw("laravel-boost")
    if k: lb = "task mentions '%s'" % k
if lb and consider("laravel-boost", lb):
    if "php" in signals or "artisan" in signals or "composer.json" in signals:
        consider("php-lsp", "PHP present — LSP for accurate PHP edits")

# 3) terraform
tf = "*.tf files present" if "terraform" in signals else None
if not tf:
    k = first_kw("terraform")
    if k: tf = "task mentions '%s'" % k
if tf: consider("terraform", tf)

# 4) swift-lsp
sw = "Swift sources / Package.swift present" if "swift" in signals else None
if not sw:
    k = first_kw("swift-lsp")
    if k: sw = "task mentions '%s'" % k
if sw: consider("swift-lsp", sw)

# 5) sentry (crash/stacktrace/exception keywords)
k = first_kw("sentry")
if k: consider("sentry", "task mentions '%s'" % k)

# 6) github (PR/issue/gh keywords)
k = first_kw("github")
if k: consider("github", "task involves a PR/issue (matched '%s')" % k)

# 7) context7 (library/version/latest/API/docs keywords)
k = first_kw("context7")
if k: consider("context7", "needs current docs — task mentions '%s'" % k)

# 8) playwright (e2e/browser keywords)
pw = "playwright config / e2e dir present" if "playwright" in signals else None
if not pw:
    k = first_kw("playwright")
    if k: pw = "task mentions '%s'" % k
if pw: consider("playwright", pw)

# code-review: matched here only so the conflict is transparent (it defers to CDT's code-reviewer agent)
k = first_kw("code-review")
if k: consider("code-review", "task mentions '%s'" % k)

# superpowers gate (CDT owns its planning/review/TDD — conflicts field => CDT wins, always)
if "superpowers" not in disabled and not cdt_owned:
    if sp_mode == "selective" and high_complexity:
        recs.append(("superpowers", "high-complexity/risk task — superpowers skills may help (CDT keeps plan/review/TDD)", True))
    elif sp_mode == "always":
        recs.append(("superpowers", "superpowers skills available (advisory; CDT keeps plan/review/TDD)", True))

if as_json:
    print(json.dumps({
        "precedence": ["cdt-orchestrator", "task-classification", "cdt-specialist-agent",
                       "plugin-skill-advisory", "validation", "cdt-verify"],
        "superpowersMode": sp_mode,
        "recommendations": [{"id": i, "reason": r, "advisory": bool(a)} for (i, r, a) in recs],
        "deferred": [{"id": i, "conflictsWith": cf, "note": "CDT wins — plugin deferred"} for (i, cf) in deferred],
    }))
    sys.exit(0)

if not recs and not deferred:
    sys.exit(0)

print("plugin routing (advisory — CDT decides): "
      "orchestrator → classify → CDT agent → plugin/skill → validate → cdt-verify")
for (i, r, a) in recs:
    print("  • %s — %s%s" % (i, r, "  [advisory]" if a else ""))
for (i, cf) in deferred:
    print("  · %s — deferred; CDT owns this (%s)" % (i, ", ".join(cf)))
sys.exit(0)
PY
exit 0
