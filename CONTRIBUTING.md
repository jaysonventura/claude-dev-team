# Contributing to claude-dev-team

Thanks for your interest! This plugin is a **discipline layer** for Claude Code — contributions that keep
it lean, grounded, and cost-effective are very welcome.

## Quick start

```bash
git clone https://github.com/jaysonventura/claude-dev-team
cd claude-dev-team
bash scripts/validate.sh        # must pass before you open a PR
```

`validate.sh` checks the JSON manifests, agent/skill/command frontmatter, and runs `shellcheck` on the
hooks. Install `shellcheck` locally (`brew install shellcheck`) so you get the same signal CI does.

## How to add things

- **An agent** — drop a markdown file in `agents/` with frontmatter (`name`, `description`, optional
  `tools`, `model`). Pin `model: opus` only for judgment roles (design/review); builders inherit the
  session model. Reference it from `skills/orchestration/SKILL.md` if the orchestrator should dispatch it.
- **A skill** — add a folder + `SKILL.md` in `skills/` with a `name` and an auto-trigger `description`.
- **A command** — add a markdown file in `commands/` with a `description` (and optional `argument-hint`,
  `allowed-tools`). It becomes `/claude-dev-team:<file>`.
- **A hook** — add the script to `hooks/`, wire it in `hooks/hooks.json` with `${CLAUDE_PLUGIN_ROOT}`.

## House rules

- **Hooks are fail-open.** Use `set +e`, guard external tools (`command -v … || exit 0`), and `exit 0` on
  every path — a hook must never break a user's session. Stay **bash 3.2-compatible** (macOS default).
- **No secrets, ever.** `*.env`, `*.db`, and build artifacts are gitignored — keep it that way. Validate
  any user-provided value before writing it to a file that gets `source`d.
- **Ground claims.** Agents and docs should reference real files/output, not invented APIs. Library
  specifics go through `context7`, not memory.
- **Keep it the user's own.** No third-party names in shipped files.
- **Update docs + `CHANGELOG.md`** for any user-visible change, and bump the version in
  `.claude-plugin/plugin.json` (the README badge and `menubar` app read from there).

## Pull requests

1. Branch from `main`, make focused changes, run `bash scripts/validate.sh`.
2. Describe **what** changed and **why**, and paste the verifying output (tests/validate).
3. CI must be green. A maintainer reviews for scope, correctness, and the house rules above.

By contributing you agree your work is licensed under the project's [MIT License](LICENSE).
