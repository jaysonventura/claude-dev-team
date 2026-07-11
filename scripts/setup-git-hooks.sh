#!/bin/sh
# setup-git-hooks.sh — activate this repo's local git hooks (commit-msg attribution scrub).
# Points core.hooksPath at scripts/git-hooks and makes the hook executable. Reversible with:
#   git config --unset core.hooksPath
set -e

repo_root=$(git rev-parse --show-toplevel 2>/dev/null) || {
  echo "setup-git-hooks: not inside a git repository"; exit 1
}
cd "$repo_root"
git config core.hooksPath scripts/git-hooks
chmod +x scripts/git-hooks/commit-msg 2>/dev/null || :
echo "setup-git-hooks: core.hooksPath = scripts/git-hooks (commit-msg scrub active for this repo)."
