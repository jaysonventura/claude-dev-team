#!/usr/bin/env bash
# cdt-worktree — safe git-worktree helper for CDT parallel isolation.
#
# Creates / lists / removes isolated checkouts under .claude/worktrees/<name> on branch
# worktree-<name>, mirroring Claude Code's own `claude --worktree <name>` convention so the two
# interoperate. Use it to run parallel CDT sessions, or to isolate parallel builders in a big T3
# wave, with zero file collisions even on shared files.
#
# Pure git — cross-platform (macOS / Linux / Windows-gitbash). Read-mostly: the only destructive
# op (`rm`) refuses a dirty / unmerged / locked worktree unless you pass --force. It never runs
# `rm -rf` on a constructed path — removal is always delegated to `git worktree remove`, and every
# <name> is validated to block path traversal and option injection.
set -u

PROG="cdt-worktree"
WT_DIR=".claude/worktrees"   # relative to repo top — mirrors `claude --worktree`

die()  { echo "$PROG: $*" >&2; exit 1; }
note() { echo "$PROG: $*"; }

need_git()  { command -v git >/dev/null 2>&1 || die "git not found (required)."; }
need_repo() { git rev-parse --is-inside-work-tree >/dev/null 2>&1 || \
              die "not inside a git repository (run from your project, or 'git init' first)."; }
# The MAIN worktree root (where .claude/worktrees/ lives) — NOT the current linked worktree. Derived
# from the shared --git-common-dir so `new`/`rm` keep targeting the main repo even when run from inside
# a worktree (the intended parallel-session case), instead of nesting worktrees inside each other.
toplevel() {
  local common
  common="$(git rev-parse --git-common-dir 2>/dev/null)" || return 1
  [ -n "$common" ] || return 1
  common="$(cd "$common" 2>/dev/null && pwd)" || return 1   # absolutize (handles relative .git)
  dirname "$common"
}

# Validate a worktree name: non-empty, no leading '-', no '..', no '/', only [A-Za-z0-9._-].
# This is the security boundary — it stops path traversal (../../etc) and option injection (-rf).
valid_name() {
  case "$1" in
    ''|-*|*..*|*/*|*[!A-Za-z0-9._-]*) return 1 ;;
    *) return 0 ;;
  esac
}

# Keep .claude/worktrees/ out of the main checkout's untracked list (official guidance). Appends one
# line to .gitignore only if no equivalent ignore is already present.
ensure_ignored() {
  local top gi line=".claude/worktrees/"
  top="$(toplevel)" || return 0
  gi="$top/.gitignore"
  if [ -f "$gi" ] && grep -qxF "$line" "$gi" 2>/dev/null; then return 0; fi
  if [ -f "$gi" ] && grep -qE '^\.claude/?($|\*|/)' "$gi" 2>/dev/null; then return 0; fi
  printf '%s\n' "$line" >> "$gi" 2>/dev/null && note "added '$line' to .gitignore"
}

cmd_new() {
  need_git; need_repo
  local name="${1:-}" base="${2:-}" top rel branch
  valid_name "$name" || die "invalid name '${name}'. Use letters, digits, '.', '_', '-' (no '/' or '..')."
  case "$base" in -*) die "invalid base ref '${base}'." ;; esac
  top="$(toplevel)"; rel="$WT_DIR/$name"; branch="worktree-$name"
  [ -e "$top/$rel" ] && die "path already exists: $rel — open it with 'claude --worktree $name', or '$PROG rm $name' first."
  ensure_ignored
  mkdir -p "$top/$WT_DIR" 2>/dev/null
  # Reuse the branch if it already exists; otherwise create it from <base> (default: current HEAD).
  if git -C "$top" show-ref --verify --quiet "refs/heads/$branch"; then
    git -C "$top" worktree add "$rel" "$branch" || die "git worktree add failed."
  elif [ -n "$base" ]; then
    git -C "$top" worktree add -b "$branch" "$rel" "$base" || die "git worktree add failed (is base '$base' a valid ref?)."
  else
    git -C "$top" worktree add -b "$branch" "$rel" || die "git worktree add failed."
  fi
  note "created $rel on branch '$branch'"
  echo "  cd \"$top/$rel\"           # work there in isolation"
  echo "  claude --worktree $name      # …or open a Claude Code session in it"
}

cmd_list() { need_git; need_repo; local top; top="$(toplevel)"; git -C "$top" worktree list; }

cmd_path() {
  need_git; need_repo
  local name="${1:-}" top p
  valid_name "$name" || die "invalid name '${name}'."
  top="$(toplevel)"; p="$top/$WT_DIR/$name"
  [ -d "$p" ] || die "no such worktree: $name"
  echo "$p"
}

cmd_rm() {
  need_git; need_repo
  local force=0 name="" a top rel err
  for a in "$@"; do
    case "$a" in
      --force|-f) force=1 ;;
      -*) die "unknown flag: $a" ;;
      *)  if [ -n "$name" ]; then die "only one worktree name allowed (got '$name' and '$a')."; fi; name="$a" ;;
    esac
  done
  valid_name "$name" || die "invalid name '${name}'."
  top="$(toplevel)"; rel="$WT_DIR/$name"
  [ -d "$top/$rel" ] || die "no such worktree: $rel"
  if [ "$force" = 1 ]; then
    git -C "$top" worktree remove --force "$rel" || die "git worktree remove failed."
    note "removed $rel (forced)"
  else
    if err="$(git -C "$top" worktree remove "$rel" 2>&1)"; then
      note "removed $rel"
    else
      die "won't remove '$name' — it has uncommitted changes, untracked files, or is locked.
       Commit/stash first, or force it: $PROG rm $name --force
       git: $err"
    fi
  fi
}

# Conservative GC: prune only stale admin metadata. Never auto-removes a real checkout — a dirty
# worktree is left intact; remove it explicitly with `rm <name> [--force]`.
cmd_clean() {
  need_git; need_repo
  local top; top="$(toplevel)"
  git -C "$top" worktree prune
  note "pruned stale worktree admin entries. Real checkouts are left intact — remove one with '$PROG rm <name>'."
}

cmd_help() {
  cat <<EOF
$PROG — isolate parallel work in git worktrees (under $WT_DIR/<name>, branch worktree-<name>).

  $PROG new <name> [base]   create an isolated checkout (base ref defaults to current HEAD)
  $PROG list                list all worktrees
  $PROG path <name>         print a worktree's absolute path (e.g. cd "\$($PROG path <name>)")
  $PROG rm <name> [--force] remove a worktree (refuses dirty/locked unless --force)
  $PROG clean               prune stale admin metadata (never removes a real checkout)
  $PROG help                this help

Interops with Claude Code: '$PROG new feat' then 'claude --worktree feat' open the same checkout.
Names allow letters, digits, '.', '_', '-' only (no '/' or '..').
EOF
}

SUB="${1:-help}"; [ $# -gt 0 ] && shift
case "$SUB" in
  new|add)        cmd_new "$@" ;;
  list|ls)        cmd_list ;;
  path)           cmd_path "$@" ;;
  rm|remove)      cmd_rm "$@" ;;
  clean|prune)    cmd_clean ;;
  help|-h|--help) cmd_help ;;
  *) die "unknown subcommand '$SUB' (try: $PROG help)" ;;
esac
