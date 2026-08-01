#!/usr/bin/env bash
# cdt-plugins — inspect & manage the CDT companion plugins, driven by the read-only registry
# (config/plugins.json). Detection is delegated ENTIRELY to the frozen plugins-lib.sh interface —
# this CLI never re-implements installed/enabled/marketplace/cli probing. Real install/enable/update
# work is shelled out to the verified `claude plugin` CLI (Claude Code 2.1.207). Read verbs are
# idempotent; write verbs are arg-escaped (no eval, no curl|sh); there is deliberately NO uninstall.
# v1.59.0
# shellcheck disable=SC2034  # registry rows are read positionally; not every column is used in every verb
set +e

CDT_HOME="${CDT_HOME:-$HOME/.claude}"
BIN="$CDT_HOME/bin"

# --- source the frozen detection library (dirname sibling, then $BIN; CDT_PLUGINS_LIB overrides) -----
_HERE="$(cd "$(dirname "$0")" 2>/dev/null && pwd)"
_LIB=""
for _c in "${CDT_PLUGINS_LIB:-}" "$_HERE/plugins-lib.sh" "$BIN/plugins-lib.sh"; do
  [ -n "$_c" ] && [ -r "$_c" ] && { _LIB="$_c"; break; }
done
if [ -z "$_LIB" ]; then
  echo "cdt-plugins: cannot find plugins-lib.sh (looked in ${_HERE} and ${BIN})." >&2
  echo "             open a fresh Claude Code session to reinstall the CLIs." >&2
  exit 1
fi
# shellcheck disable=SC1090
. "$_LIB"

# --- env-driven policy knobs (same on/off token style as config.sh) ---------------------------------
# All knobs resolve via plib_cfg: process env wins if SET, else the persisted ~/.claude env file, else the
# default — so `cdt-config plugin-strict off` etc. actually change behavior in a standalone subprocess.
strict_on() {        # CDT_PLUGIN_STRICT — default ON; off only for an explicit off token
  case "$(printf '%s' "$(plib_cfg CDT_PLUGIN_STRICT 1)" | tr '[:upper:]' '[:lower:]')" in
    0|off|false|no) return 1 ;; *) return 0 ;;
  esac
}
auto_install_on() {  # CDT_PLUGIN_AUTO_INSTALL — default OFF
  case "$(printf '%s' "$(plib_cfg CDT_PLUGIN_AUTO_INSTALL 0)" | tr '[:upper:]' '[:lower:]')" in
    1|on|true|yes) return 0 ;; *) return 1 ;;
  esac
}
auto_update_on() {   # CDT_PLUGIN_AUTO_UPDATE — default OFF
  case "$(printf '%s' "$(plib_cfg CDT_PLUGIN_AUTO_UPDATE 0)" | tr '[:upper:]' '[:lower:]')" in
    1|on|true|yes) return 0 ;; *) return 1 ;;
  esac
}

# effective_scope <registry_scope> — CDT_PLUGIN_SCOPE (via plib_cfg) overrides the per-plugin registry
# default when set to a valid value (user|project); else the registry scope stands.
effective_scope() {
  local reg_scope="${1:-}" ov
  ov="$(plib_cfg CDT_PLUGIN_SCOPE '' 2>/dev/null)"
  case "$ov" in user|project) printf '%s\n' "$ov"; return 0 ;; esac
  printf '%s\n' "$reg_scope"
}

# valid_ident <ident> — rc0 iff <ident> matches the install-identifier grammar (defense-in-depth before
# any `claude plugin` shell-out, matching _acquire).
valid_ident() { printf '%s' "${1:-}" | grep -Eq '^[A-Za-z0-9._-]+@[A-Za-z0-9._-]+$'; }

# _meta rows use ASCII Unit Separator (0x1F) between fields — a NON-whitespace delimiter, so `read`/`cut`
# preserve empty fields (an empty cliDeps/binaries column must not collapse and shift the others).
US="$(printf '\037')"

# --- cached bulk detection (frozen listers, queried once per run) ------------------------------------
INSTALLED_CACHE=""; MKT_CACHE=""
_cache_installed() { INSTALLED_CACHE="$(plib_installed 2>/dev/null | cut -f1)"; }
_cache_mkts()      { MKT_CACHE="$(plib_marketplaces 2>/dev/null)"; }
is_inst() { printf '%s\n' "$INSTALLED_CACHE" | grep -Fxq "$1"; }
has_mkt() { printf '%s\n' "$MKT_CACHE" | grep -Fxq "$1"; }

# --- static registry metadata (read-only config; NOT detection) -------------------------------------
# One TAB row per plugin, columns:
#   1 id  2 type  3 marketplace  4 scope  5 required  6 needsAuth  7 securityLevel  8 fallbackBehavior
#   9 installIdentifier  10 enabledByDefault  11 cliDeps(comma)  12 binDeps(; )  13 taskKeywords(comma)
#  14 repoSignals(comma)  15 displayName
_meta() {
  local _reg; _reg="$(plib_load_registry 2>/dev/null)"
  [ -n "$_reg" ] || return 0
  CDT_REG_JSON="$_reg" python3 - <<'PY'
import json, os, sys
try:
    reg = json.loads(os.environ.get("CDT_REG_JSON", ""))
except Exception:
    sys.exit(0)
def b(x): return "true" if x else "false"
for p in (reg.get("plugins", []) if isinstance(reg, dict) else []):
    if not isinstance(p, dict):
        continue
    ar = p.get("activationRules") or {}
    dep = p.get("dependencies") or {}
    row = [
        p.get("id", ""), p.get("type", ""), p.get("marketplace") or "", p.get("scope", ""),
        b(p.get("required")), b(p.get("needsAuth")), p.get("securityLevel", ""),
        p.get("fallbackBehavior", ""), p.get("installIdentifier") or "", b(p.get("enabledByDefault")),
        ",".join(dep.get("cli") or []), "; ".join(dep.get("binaries") or []),
        ",".join(ar.get("taskKeywords") or []), ",".join(ar.get("repoSignals") or []),
        p.get("displayName", ""),
    ]
    print("\x1f".join(str(x) for x in row))
PY
}

# meta_row <id> — echo the one metadata row for <id> (US-delimited); rc1 if the id is not in the registry.
meta_row() { _meta | awk -F"$US" -v id="$1" '$1==id{print; f=1} END{exit(f?0:1)}'; }

# mkt_source <id> — echo the registry's optional `marketplaceSource` (an "owner/repo" slug) for <id>, so we
# can print the exact `claude plugin marketplace add …` a user needs before the install can work. Empty when
# absent — official rows omit it because claude-plugins-official ships configured. Read via its own lookup
# on purpose: appending a 16th column to the US-delimited _meta row would silently land in `disp` for any
# `read -r` consumer that wasn't updated.
mkt_source() {
  local _id="${1:-}" _reg; [ -n "$_id" ] || return 0
  _reg="$(plib_load_registry 2>/dev/null)"; [ -n "$_reg" ] || return 0
  CDT_REG_JSON="$_reg" CDT_MS_ID="$_id" python3 - <<'PY'
import json, os, sys
try:
    reg = json.loads(os.environ.get("CDT_REG_JSON", ""))
except Exception:
    sys.exit(0)
rid = os.environ.get("CDT_MS_ID", "")
for p in (reg.get("plugins", []) if isinstance(reg, dict) else []):
    if isinstance(p, dict) and p.get("id") == rid:
        src = p.get("marketplaceSource") or ""
        if src:
            print(str(src))
        break
PY
}

# --- gather: registry ⨝ installed ⨝ enabled ⨝ cli-probe ⨝ marketplace, one computed record per plugin -
# Output TAB columns: 1 id  2 type  3 glyph  4 status  5 installed  6 enabled  7 note  8 required
gather() {
  _cache_installed; _cache_mkts
  # shellcheck disable=SC2034  # all columns are positional read targets; not every one is referenced
  local id type mkt scope req needsauth sec fb ident endef clis bins kw sig disp
  while IFS="$US" read -r id type mkt scope req needsauth sec fb ident endef clis bins kw sig disp; do
    [ -n "$id" ] || continue
    local installed=false enabled=false mkt_ok=true miss=""
    if [ "$type" = "cdt-skill" ]; then
      installed=true; enabled=true
    else
      is_inst "$id" && installed=true
      plib_is_enabled "$id" 2>/dev/null && enabled=true
    fi
    [ -n "$mkt" ] && { has_mkt "$mkt" || mkt_ok=false; }
    if [ -n "$clis" ]; then
      local _c _old="$IFS"; IFS=','
      for _c in $clis; do
        [ -n "$_c" ] || continue
        plib_probe_cli "$_c" >/dev/null 2>&1 || miss="${miss:+$miss, }$_c"
      done
      IFS="$_old"
    fi
    local glyph status note
    if [ "$type" = "cdt-skill" ]; then
      glyph="✓"; status="local"; note="local CDT skill — always available"
    elif [ "$mkt_ok" = false ]; then
      # BEFORE the not-installed branch: an unconfigured marketplace is WHY the install is missing, and
      # `cdt-plugins install <id>` cannot succeed until it is added. Ordering this after `installed=false`
      # made the branch unreachable in the only case it matters and handed out a dead-end command.
      local _src; _src="$(mkt_source "$id")"
      glyph="⨯"; status="missing-dep"
      if [ -n "$_src" ]; then
        note="marketplace not configured: $mkt (add: claude plugin marketplace add $_src)"
      else
        note="marketplace not configured: $mkt"
      fi
    elif [ "$installed" = false ]; then
      glyph="○"; status="available"; note="available — not installed (install: cdt-plugins install $id)"
    elif [ -n "$miss" ]; then
      glyph="⨯"; status="missing-dep"; note="missing CLI: $miss"
    elif [ "$enabled" = false ]; then
      glyph="○"; status="disabled"; note="installed but disabled (enable: cdt-plugins enable $id)"
    elif [ "$needsauth" = true ]; then
      glyph="!"; status="needs-auth"; note="enabled — needs auth (connect: /mcp)"
    elif [ -n "$bins" ]; then
      glyph="!"; status="needs-setup"; note="enabled — external setup: $bins"
    else
      glyph="✓"; status="healthy"; note="installed + enabled"
    fi
    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
      "$id" "$type" "$glyph" "$status" "$installed" "$enabled" "$note" "$req"
  done <<EOF
$(_meta)
EOF
}

# _json_rows — id=status lines for plib_emit_json (flat {id: status} object).
_json_rows() { gather 2>/dev/null | awk -F'\t' 'NF>=8{print $1"="$4}'; }

# count_broken — number of REQUIRED plugins that are not installed / missing-dep / disabled.
count_broken() {
  gather 2>/dev/null | awk -F'\t' '$8=="true" && ($4=="available"||$4=="missing-dep"||$4=="disabled")' | grep -c .
}

BROKEN_COUNT=0
render_table() {   # <mode: list|doctor>
  local mode="$1" recs
  recs="$(gather)"
  BROKEN_COUNT=0
  if [ -z "$recs" ]; then
    echo "cdt-plugins: no plugins resolved — registry unreadable? (path: $(plib_registry_path))"
    return 0
  fi
  local total inst en
  total=$(printf '%s\n' "$recs" | grep -c .)
  inst=$(printf '%s\n' "$recs" | awk -F'\t' '$5=="true"' | grep -c .)
  en=$(printf '%s\n' "$recs" | awk -F'\t' '$6=="true"' | grep -c .)
  printf 'cdt-plugins — %s registered · %s installed · %s enabled\n' "$total" "$inst" "$en"
  printf '%s\n' "$recs" | while IFS=$'\t' read -r id type glyph status installed enabled note req; do
    printf '  %s %-18s %-20s %s\n' "$glyph" "$id" "$type" "$note"
  done
  echo "  legend: ✓ healthy · ! needs attention · ○ available/disabled · ⨯ missing dependency"
  if [ "$mode" = doctor ]; then
    BROKEN_COUNT=$(printf '%s\n' "$recs" | awk -F'\t' '$8=="true" && ($4=="available"||$4=="missing-dep"||$4=="disabled")' | grep -c .)
    echo "  required plugins broken: $BROKEN_COUNT   (non-required issues are warnings only)"
  fi
}

# ---------------------------------------------------------------------------------------------------
cmd_list() {   # list | status  [--json]
  if [ "${1:-}" = "--json" ]; then plib_emit_json _json_rows; return 0; fi
  render_table list
}

cmd_doctor() {
  local json=0; [ "${1:-}" = "--json" ] && json=1
  local rc=0
  command -v python3 >/dev/null 2>&1 || { echo "cdt-plugins: ⨯ python3 missing (core dependency) — run: cdt-deps --install"; rc=2; }
  if [ "$json" = 1 ]; then
    plib_emit_json _json_rows
    BROKEN_COUNT=$(count_broken)
  else
    render_table doctor
  fi
  [ "${BROKEN_COUNT:-0}" -gt 0 ] && rc=2
  return $rc
}

cmd_explain() {
  local id="${1:-}"
  [ -n "$id" ] || { echo "usage: cdt-plugins explain <id>"; return 2; }
  local row; row="$(meta_row "$id")" || {
    echo "cdt-plugins: unknown plugin '$id' — not in the CDT registry. See: cdt-plugins list"; return 2; }
  # shellcheck disable=SC2034  # all columns are positional read targets; not every one is referenced
  local m_type m_mkt m_scope m_req m_auth m_sec m_fb m_ident m_edef m_cli m_bin m_kw m_sig m_disp
  IFS="$US" read -r _ m_type m_mkt m_scope m_req m_auth m_sec m_fb m_ident m_edef m_cli m_bin m_kw m_sig m_disp <<<"$row"
  _cache_installed
  local installed=no enabled=no overlay
  if [ "$m_type" = "cdt-skill" ]; then installed="n/a (local)"; enabled="n/a (local)"
  else is_inst "$id" && installed=yes; plib_is_enabled "$id" 2>/dev/null && enabled=yes; fi
  overlay="$(plib_state_get "$id" 2>/dev/null)"
  # which of this plugin's repo signals fire in the current directory?
  local match="no"
  if [ -n "$m_sig" ]; then
    local fired _s _o="$IFS"; fired="$(plib_detect_signals "$PWD" 2>/dev/null)"
    IFS=','
    for _s in $m_sig; do printf '%s\n' "$fired" | grep -Fxq "$_s" && { match="yes ($_s)"; break; }; done
    IFS="$_o"
  fi
  echo "$m_disp  ($id)"
  echo "  type            : $m_type"
  echo "  marketplace     : ${m_mkt:-(local — none)}   scope: $m_scope"
  echo "  install id      : ${m_ident:-(local — none)}   default-on: $m_edef"
  echo "  routes on:"
  echo "     keywords     : ${m_kw:-(none)}"
  echo "     repo signals : ${m_sig:-(none)}"
  echo "     fires here?  : $match"
  echo "  dependencies    : cli=[${m_cli:-none}]  binaries=[${m_bin:-none}]"
  if [ "$m_auth" = true ]; then
    echo "  needs auth      : yes  → connect with /mcp (cdt-plugins never auto-authenticates)"
  else
    echo "  needs auth      : no"
  fi
  echo "  security level  : $m_sec   ·   required: $m_req   ·   fallback: $m_fb"
  echo "  state           : installed=$installed  enabled=$enabled  overlay=$overlay"
}

cmd_sync() {
  _cache_installed; _cache_mkts   # MKT_CACHE is required by has_mkt below — without it every lookup fails
  local run=0; auto_install_on && ! strict_on && run=1
  local do_update=0; auto_update_on && ! strict_on && do_update=1
  echo "cdt-plugins sync — remediation for missing enabled plugins:"
  local any=0
  # shellcheck disable=SC2034  # all columns are positional read targets; not every one is referenced
  local id type mkt scope req needsauth sec fb ident endef clis bins kw sig disp
  while IFS="$US" read -r id type mkt scope req needsauth sec fb ident endef clis bins kw sig disp; do
    [ -n "$id" ] || continue
    [ "$type" = "cdt-skill" ] && continue
    [ -n "$ident" ] || continue
    valid_ident "$ident" || continue                          # defense-in-depth before any shell-out
    local state; state="$(plib_state_get "$id" 2>/dev/null)"
    case "$state" in enabled|auto) ;; *) continue ;; esac      # only desired-active plugins
    scope="$(effective_scope "$scope")"                        # CDT_PLUGIN_SCOPE override, if set
    local installed=no enabled=no
    is_inst "$id" && installed=yes
    plib_is_enabled "$id" 2>/dev/null && enabled=yes
    # auto-update: idempotently refresh already-installed desired-active plugins (gated + arg-escaped)
    if [ "$do_update" = 1 ] && [ "$installed" = yes ]; then
      any=1
      echo "  → claude plugin update $ident -s $scope"
      claude plugin update "$ident" -s "$scope" 2>&1 | plib_redact
    fi
    local verb=""
    [ "$installed" = no ] && verb="install"
    [ "$installed" = yes ] && [ "$enabled" = no ] && verb="enable"
    [ -n "$verb" ] || continue
    any=1
    # An install cannot resolve until its marketplace is configured, so emit that prerequisite first rather
    # than a command that is guaranteed to fail. Never auto-run it — adding a marketplace is a trust
    # decision that stays with the user, even when auto-install is on.
    if [ "$verb" = "install" ] && [ -n "$mkt" ] && ! has_mkt "$mkt"; then
      local _src; _src="$(mkt_source "$id")"
      if [ -n "$_src" ]; then
        echo "  claude plugin marketplace add $_src   # prerequisite: marketplace '$mkt' not configured"
      else
        echo "  # prerequisite: marketplace '$mkt' is not configured — add it before the install below"
      fi
    fi
    local cmd="claude plugin $verb $ident -s $scope"
    if [ "$run" = 1 ]; then
      echo "  → $cmd"
      claude plugin "$verb" "$ident" -s "$scope" 2>&1 | plib_redact
    else
      echo "  $cmd"
    fi
  done <<EOF
$(_meta)
EOF
  if [ "$any" = 0 ]; then
    echo "  ✓ all enabled plugins present — nothing to sync."
  elif [ "$run" = 0 ]; then
    echo "  (advisory — nothing was run. To apply: CDT_PLUGIN_AUTO_INSTALL=1 CDT_PLUGIN_STRICT=0 cdt-plugins sync)"
  fi
}

# enable/disable: set the overlay, then shell out to `claude plugin enable|disable`.
_toggle() {
  local verb="$1" id="${2:-}"
  [ -n "$id" ] || { echo "usage: cdt-plugins $verb <id>"; return 2; }
  local row; row="$(meta_row "$id")" || {
    echo "cdt-plugins: unknown plugin '$id' — not in the CDT registry."; return 2; }
  local ident scope type
  type="$(printf '%s' "$row" | cut -d"$US" -f2)"
  scope="$(printf '%s' "$row" | cut -d"$US" -f4)"
  ident="$(printf '%s' "$row" | cut -d"$US" -f9)"
  local ostate; [ "$verb" = enable ] && ostate=enabled || ostate=disabled
  plib_state_set "$id" "$ostate" && echo "cdt-plugins: overlay '$id' → $ostate"
  if [ "$type" = "cdt-skill" ] || [ -z "$ident" ]; then
    echo "cdt-plugins: '$id' is a local CDT skill — overlay updated; no Claude Code plugin to $verb."
    return 0
  fi
  if ! valid_ident "$ident"; then
    echo "cdt-plugins: refusing — install identifier '$ident' failed validation."; return 2
  fi
  scope="$(effective_scope "$scope")"
  echo "  → claude plugin $verb $ident -s $scope"
  claude plugin "$verb" "$ident" -s "$scope" 2>&1 | plib_redact
}

# install/update: validate against registry + identifier grammar, gate third-party behind strict.
_acquire() {
  local verb="$1" id="${2:-}"
  [ -n "$id" ] || { echo "usage: cdt-plugins $verb <id>"; return 2; }
  local row; row="$(meta_row "$id")" || {
    echo "cdt-plugins: refusing — '$id' is not in the CDT registry."; return 2; }
  local type ident sec scope auth
  type="$(printf '%s' "$row" | cut -d"$US" -f2)"
  scope="$(printf '%s' "$row" | cut -d"$US" -f4)"
  auth="$(printf '%s' "$row" | cut -d"$US" -f6)"
  sec="$(printf '%s' "$row" | cut -d"$US" -f7)"
  ident="$(printf '%s' "$row" | cut -d"$US" -f9)"
  if [ "$type" = "cdt-skill" ] || [ -z "$ident" ]; then
    echo "cdt-plugins: '$id' is a local CDT skill — always available, nothing to $verb."
    return 0
  fi
  if ! valid_ident "$ident"; then
    echo "cdt-plugins: refusing — install identifier '$ident' failed validation."; return 2
  fi
  scope="$(effective_scope "$scope")"
  local cmd="claude plugin $verb $ident -s $scope"
  if [ "$sec" != "official" ] && strict_on; then
    echo "cdt-plugins: '$id' is $sec (not official) and strict mode is ON — not executing."
    echo "  run it yourself : $cmd"
    echo "  or override once: CDT_PLUGIN_STRICT=0 cdt-plugins $verb $id"
    return 0
  fi
  echo "  → $cmd"
  claude plugin "$verb" "$ident" -s "$scope" 2>&1 | plib_redact
  [ "$auth" = true ] && echo "cdt-plugins: '$id' needs auth — connect it with /mcp (no auto-auth performed)."
  return 0
}

usage() {
  cat <<'USAGE'
cdt-plugins — inspect & manage the CDT companion plugins (registry-driven; detection is read-only).

  list | status [--json]   health table: registry ⨝ installed ⨝ enabled ⨝ deps ⨝ overlay
  doctor [--json]          same table; exits non-zero only if a REQUIRED plugin / core dep is broken
  explain <id>             type, routing rules, deps, auth, security & fallback for one plugin
  sync                     print `claude plugin install/enable …` for missing enabled plugins
                           (only runs them with CDT_PLUGIN_AUTO_INSTALL=1 and CDT_PLUGIN_STRICT=0)
  enable  <id>             overlay=enabled  + claude plugin enable
  disable <id>             overlay=disabled + claude plugin disable
  install <id>             claude plugin install  (third-party gated by CDT_PLUGIN_STRICT, default on)
  update  <id>             claude plugin update

  no uninstall (no destructive removal) · needs-auth plugins get a /mcp hint, never auto-auth.
USAGE
}

case "${1:-list}" in
  list|status)     cmd_list "${2:-}" ;;
  doctor)          cmd_doctor "${2:-}" ;;
  explain)         cmd_explain "${2:-}" ;;
  sync)            cmd_sync ;;
  enable)          _toggle enable "${2:-}" ;;
  disable)         _toggle disable "${2:-}" ;;
  install)         _acquire install "${2:-}" ;;
  update)          _acquire update "${2:-}" ;;
  -h|--help|help)  usage ;;
  *) echo "cdt-plugins: unknown command '${1}'"; echo; usage; exit 2 ;;
esac
exit $?
