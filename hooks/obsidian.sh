#!/usr/bin/env bash
# cdt-obsidian — export the CDT vault (~/.claude/vault) into an Obsidian vault as linked markdown.
#
#   cdt-obsidian sync           export / re-sync the vault now
#   cdt-obsidian status         show configured path + last sync time
#   cdt-obsidian set <path>     configure the Obsidian vault path (writes CDT_OBSIDIAN_VAULT)
#   cdt-obsidian hook           session-end Stop hook entrypoint (once/session, fail-open)
#
# Fail-open: every code path ends with exit 0 to never block a Claude Code session.
set +e

# Recursion guard (same pattern as session-start-vault.sh line 8)
[ "${CDT_IN_ENHANCER:-0}" = "1" ] && exit 0

CDT_HOME="$HOME/.claude"
VAULT_SRC="$CDT_HOME/vault"
ENV_FILE="$CDT_HOME/claude-dev-team.env"
DEFAULT_OBS_ROOT="$HOME/Documents/Obsidian"
DEFAULT_OBS_VAULT="$DEFAULT_OBS_ROOT/CDT"

# ── helpers ──────────────────────────────────────────────────────────────────

# Read env key without sourcing (security: a crafted value must never execute — see session-start-vault.sh line 82)
genv() { grep -E "^$1=" "$ENV_FILE" 2>/dev/null | head -1 | cut -d= -f2-; }

set_env() {
  local key="$1" val="$2" tmp
  tmp="$(mktemp 2>/dev/null || echo "$ENV_FILE.tmp")"
  grep -v -E "^${key}=" "$ENV_FILE" 2>/dev/null > "$tmp"
  printf '%s=%s\n' "$key" "$val" >> "$tmp"
  mv "$tmp" "$ENV_FILE" 2>/dev/null
  chmod 600 "$ENV_FILE" 2>/dev/null
}

resolve_vault() {
  # Returns the target Obsidian vault dir (CDT subfolder).
  # Priority: shell env (CDT_OBSIDIAN_VAULT) > env file > default path.
  local configured
  # Allow the shell environment to override (enables smoke-testing without touching the env file)
  configured="${CDT_OBSIDIAN_VAULT:-$(genv CDT_OBSIDIAN_VAULT)}"
  if [ -n "$configured" ]; then
    printf '%s' "$configured"
  else
    printf '%s' "$DEFAULT_OBS_VAULT"
  fi
}

resolve_recall_root() {
  # Search root for read-back recall. Default: the whole Obsidian vault (the PARENT of the CDT
  # subfolder) so the user's own curated notes are included — not just CDT's synced output.
  # Override with CDT_OBSIDIAN_RECALL_ROOT (shell env > env file).
  local r vault
  r="${CDT_OBSIDIAN_RECALL_ROOT:-$(genv CDT_OBSIDIAN_RECALL_ROOT)}"
  if [ -n "$r" ]; then printf '%s' "$r"; return; fi
  vault="$(resolve_vault)"
  case "$(basename "$vault")" in
    CDT|cdt) dirname "$vault" ;;
    *) printf '%s' "$vault" ;;
  esac
}

# Enabled when sync is explicitly ON, OR a vault path has been configured
# (setting a path auto-enables — "auto use"). An explicit `off` always wins.
obsidian_enabled() {
  local val vault
  val="${CDT_OBSIDIAN:-$(genv CDT_OBSIDIAN)}"
  [ "$val" = "off" ] && return 1
  [ "$val" = "on" ] && return 0
  vault="${CDT_OBSIDIAN_VAULT:-$(genv CDT_OBSIDIAN_VAULT)}"
  [ -n "$vault" ]
}

# ── sub-commands ──────────────────────────────────────────────────────────────

cmd_status() {
  local obs_val vault_dir
  vault_dir="$(genv CDT_OBSIDIAN_VAULT)"
  if obsidian_enabled; then
    obs_val="on"; [ "$(genv CDT_OBSIDIAN)" != "on" ] && obs_val="on (auto — path set)"
  else
    obs_val="off"
  fi

  echo "cdt-obsidian status:"
  echo "  obsidian sync : $obs_val"
  if [ -n "$vault_dir" ]; then
    echo "  vault path    : $vault_dir"
    if [ -d "$vault_dir" ]; then
      if [ -f "$vault_dir/.cdt-last-sync" ]; then
        echo "  last sync     : $(cat "$vault_dir/.cdt-last-sync" 2>/dev/null || echo unknown)"
      else
        echo "  last sync     : never"
      fi
    else
      echo "  last sync     : (vault dir does not exist yet)"
    fi
  else
    echo "  vault path    : not configured (default would be: $DEFAULT_OBS_VAULT)"
    echo "  last sync     : never"
    echo
    echo "  Enable:    cdt-config obsidian-vault ~/Documents/Obsidian/CDT   (setting a path auto-enables sync)"
  fi
  exit 0
}

cmd_set() {
  local path="$1"
  if [ -z "$path" ]; then
    echo "cdt-obsidian: usage: cdt-obsidian set <path>"
    exit 0
  fi
  set_env CDT_OBSIDIAN_VAULT "$path"
  echo "cdt-obsidian: vault path set to: $path"
  echo "  Enable sync: cdt-config obsidian on"
  exit 0
}

# Convert a filename (without extension) to a [[wikilink]]-friendly title.
to_title() {
  # Replace hyphens/underscores with spaces, title-case via awk (BSD tr only takes single chars per set)
  printf '%s' "$1" | tr '-' ' ' | tr '_' ' ' | awk '{for(i=1;i<=NF;i++) $i=toupper(substr($i,1,1)) substr($i,2); print}'
}

# Write a single file's converted markdown to the destination.
# Adds YAML frontmatter, rewrites [[wikilink]] references to relative files.
export_file() {
  local src="$1" dest_dir="$2" rel_label="$3"
  local fname base title dest now

  fname="$(basename "$src")"
  base="${fname%.md}"
  title="$(to_title "$base")"
  dest="$dest_dir/$fname"
  now="$(date '+%Y-%m-%d %H:%M:%S' 2>/dev/null || echo unknown)"

  # Build frontmatter + body. Use python3 if available for wikilink rewriting,
  # else fall back to a simpler awk pass. Always fail-open.
  if command -v python3 >/dev/null 2>&1; then
    SRC="$src" DEST="$dest" TITLE="$title" LABEL="$rel_label" NOW="$now" \
    python3 - <<'PY'
import os, re, sys

src   = os.environ["SRC"]
dest  = os.environ["DEST"]
title = os.environ["TITLE"]
label = os.environ["LABEL"]
now   = os.environ["NOW"]

try:
    body = open(src, "r", encoding="utf-8", errors="replace").read()
except Exception as e:
    print(f"cdt-obsidian: could not read {src}: {e}", file=sys.stderr)
    sys.exit(0)

# Skip files that are already managed (no double-frontmatter).
# Strip any existing CDT-managed frontmatter block.
MARKER = "<!-- cdt-obsidian-managed -->"
if MARKER in body:
    # Remove old frontmatter up to the first blank line after the closing ---
    body = re.sub(r'^---\n.*?\n---\n', '', body, count=1, flags=re.DOTALL)
    body = body.lstrip('\n')

# Rewrite bare markdown links [text](file.md) → [[File Title|text]] style wikilinks
# and preserve existing [[wikilinks]] as-is.
def md_link_to_wiki(m):
    text = m.group(1)
    href = m.group(2)
    if href.startswith("http://") or href.startswith("https://"):
        return m.group(0)   # keep external links as-is
    # strip .md suffix, convert path separators
    ref = re.sub(r'\.md$', '', href).replace('/', ' ').replace('-', ' ').replace('_', ' ')
    ref = ' '.join(w.capitalize() for w in ref.split())
    if text and text != ref:
        return f"[[{ref}|{text}]]"
    return f"[[{ref}]]"

body = re.sub(r'\[([^\]]*)\]\(([^)]+)\)', md_link_to_wiki, body)

frontmatter = f"""---
title: "{title}"
source: "cdt-vault/{label}"
synced: "{now}"
tags: [cdt, vault]
---
{MARKER}

"""

try:
    os.makedirs(os.path.dirname(dest) if os.path.dirname(dest) else ".", exist_ok=True)
    with open(dest, "w", encoding="utf-8") as f:
        f.write(frontmatter + body)
except Exception as e:
    print(f"cdt-obsidian: could not write {dest}: {e}", file=sys.stderr)
    sys.exit(0)
PY
  else
    # Minimal fallback: copy with a simple frontmatter header (no wikilink conversion).
    {
      printf '---\ntitle: "%s"\nsource: "cdt-vault/%s"\ntags: [cdt, vault]\n---\n<!-- cdt-obsidian-managed -->\n\n' \
        "$title" "$rel_label"
      cat "$src" 2>/dev/null
    } > "$dest" 2>/dev/null
  fi
}

generate_index() {
  local obs_dir="$1" now="$2"
  local index="$obs_dir/CDT Index.md"

  {
    printf '---\ntitle: "CDT Index"\ntags: [cdt, index, moc]\nsynced: "%s"\n---\n<!-- cdt-obsidian-managed -->\n\n' "$now"
    printf '# CDT Vault — Map of Content\n\n'
    printf '_Auto-generated by `cdt-obsidian sync`. Last updated: %s_\n\n' "$now"
    printf '%s\n' "## Core" ""
    [ -f "$obs_dir/README.md" ]    && printf '%s\n' "- [[README]]"
    [ -f "$obs_dir/learnings.md" ] && printf '%s\n' "- [[learnings|Learnings]]"
    [ -f "$obs_dir/log.md" ]       && printf '%s\n' "- [[log|Log]]"

    if [ -d "$obs_dir/sessions" ] && [ "$(ls -A "$obs_dir/sessions" 2>/dev/null)" ]; then
      printf '%s\n' "" "## Sessions" ""
      for f in "$obs_dir/sessions/"*.md; do
        [ -f "$f" ] || continue
        base="$(basename "$f" .md)"
        title="$(to_title "$base")"
        printf '%s\n' "- [[sessions/$base|$title]]"
      done
    fi

    if [ -d "$obs_dir/adrs" ] && [ "$(ls -A "$obs_dir/adrs" 2>/dev/null)" ]; then
      printf '%s\n' "" "## Architecture Decisions" ""
      for f in "$obs_dir/adrs/"*.md; do
        [ -f "$f" ] || continue
        base="$(basename "$f" .md)"
        title="$(to_title "$base")"
        printf '%s\n' "- [[adrs/$base|$title]]"
      done
    fi
  } > "$index" 2>/dev/null
}

cmd_sync() {
  local obs_dir now

  obs_dir="$(resolve_vault)"
  now="$(date '+%Y-%m-%d %H:%M:%S' 2>/dev/null || echo unknown)"

  # Guard: source vault must exist
  if [ ! -d "$VAULT_SRC" ]; then
    echo "cdt-obsidian: source vault not found: $VAULT_SRC" >&2
    exit 0
  fi

  # Create the target directory tree (do NOT remove existing files — merge only)
  mkdir -p "$obs_dir/sessions" "$obs_dir/adrs" 2>/dev/null
  if [ ! -d "$obs_dir" ]; then
    echo "cdt-obsidian: could not create vault dir: $obs_dir" >&2
    exit 0
  fi

  local exported=0

  # Export top-level files
  for f in README.md learnings.md log.md; do
    [ -f "$VAULT_SRC/$f" ] && export_file "$VAULT_SRC/$f" "$obs_dir" "$f" && exported=$((exported+1))
  done

  # Export sessions/*.md
  if [ -d "$VAULT_SRC/sessions" ]; then
    for f in "$VAULT_SRC/sessions/"*.md; do
      [ -f "$f" ] || continue
      export_file "$f" "$obs_dir/sessions" "sessions/$(basename "$f")"
      exported=$((exported+1))
    done
  fi

  # Export adrs/*.md
  if [ -d "$VAULT_SRC/adrs" ]; then
    for f in "$VAULT_SRC/adrs/"*.md; do
      [ -f "$f" ] || continue
      export_file "$f" "$obs_dir/adrs" "adrs/$(basename "$f")"
      exported=$((exported+1))
    done
  fi

  # (Re)generate the index / Map of Content
  generate_index "$obs_dir" "$now"

  # Stamp last-sync
  printf '%s\n' "$now" > "$obs_dir/.cdt-last-sync" 2>/dev/null

  echo "cdt-obsidian: synced $exported file(s) → $obs_dir  ($now)"
  exit 0
}

cmd_hook() {
  # Stop hook entrypoint — called by hooks.json on session end.
  # Fail-open contract: MUST exit 0 always, run at most ONCE per session.

  # Read session id from stdin (hooks pass a JSON payload)
  _HOOK_INPUT="$(cat 2>/dev/null)"
  SESSION_ID="$(printf '%s' "$_HOOK_INPUT" | \
    sed -n 's/.*"session_id"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)"
  # Fall back to a per-process guard if session_id is unavailable
  [ -z "$SESSION_ID" ] && SESSION_ID="$$"

  GUARD="${TMPDIR:-/tmp}/cdt-obsidian-synced-${SESSION_ID}.marker"

  # Once-per-session guard
  if [ -f "$GUARD" ]; then
    exit 0
  fi

  # Only run when explicitly enabled
  if ! obsidian_enabled; then
    exit 0
  fi

  # Resolve vault path — require it to be set (either configured or default exists)
  obs_dir="$(resolve_vault)"
  # If using default and parent doesn't exist, skip silently rather than creating ~/Documents/Obsidian
  # unexpectedly.
  configured_path="${CDT_OBSIDIAN_VAULT:-$(genv CDT_OBSIDIAN_VAULT)}"
  if [ -z "$configured_path" ] && [ ! -d "$DEFAULT_OBS_ROOT" ]; then
    exit 0
  fi

  # Mark done BEFORE sync so a crash/kill doesn't retry endlessly this session.
  touch "$GUARD" 2>/dev/null

  # Run the sync quietly; any error is swallowed (fail-open).
  cmd_sync >/dev/null 2>&1 || true

  exit 0
}

# Read-back recall: rank the Obsidian vault (your curated notes + synced CDT content) for a query
# and print the top matches. Gated on enabled+configured; silent no-op otherwise (fail-open) so the
# orchestrator's Wave-0 recall can always append it without risk.
cmd_recall() {
  local query="$1" n="${2:-5}" root helper out
  obsidian_enabled || exit 0
  [ -n "$query" ] || exit 0
  command -v python3 >/dev/null 2>&1 || exit 0
  root="$(resolve_recall_root)"
  [ -d "$root" ] || exit 0
  helper="$(dirname "$0")/obsidian_recall.py"
  [ -f "$helper" ] || exit 0
  out="$(python3 "$helper" "$root" "$query" "$n" 2>/dev/null)"
  [ -n "$out" ] || exit 0
  printf '## Relevant Obsidian notes\n%s\n' "$out"
}

# ── dispatch ──────────────────────────────────────────────────────────────────

CMD="${1:-status}"
shift 2>/dev/null || true

case "$CMD" in
  sync)   cmd_sync   ;;
  status) cmd_status ;;
  set)    cmd_set "$1" ;;
  hook)   cmd_hook   ;;
  recall) cmd_recall "$1" "$2" ;;
  *)
    echo "usage: cdt-obsidian {sync|status|set <path>|recall <query> [N]|hook}"
    echo
    echo "  sync             export ~/.claude/vault into the configured Obsidian vault"
    echo "  status           show configured path and last sync time"
    echo "  set <path>       configure the Obsidian vault path"
    echo "  recall <q> [N]   rank the Obsidian vault for <q>; print the top-N notes (read-back)"
    echo "  hook             Stop-hook entrypoint (once/session, fail-open)"
    exit 0
    ;;
esac
exit 0
