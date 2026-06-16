---
name: automation-first
description: Use BEFORE running any build, deploy, run, release, or env command. Prefer existing repo automation over improvised manual commands — inspect the Makefile first, then package/composer scripts, scripts/, docs/CI. Stops agents inventing serverless / gradle / npm·ng build / cap sync / AWS deploy commands when a target already exists; on a Makefile-target failure, STOP and report instead of improvising another path.
---

# Automation-first — prefer repo automation over manual commands

LLM agents love to hand-write a deploy/build command. That drifts from how the repo is actually run,
skips env wiring the team baked into a target, and improvises new paths when one fails. Don't. **Inspect
the repo's automation and use it.**

## Command hierarchy (highest wins — use the first that applies)

1. **Explicit user command** — the exact command the user gave you, verbatim.
2. **Makefile target** — `make <target>` (this repo's primary entrypoint).
3. **Package / composer scripts** — `package.json` `"scripts"`, `composer.json` `"scripts"`, `Taskfile.yml`, `Justfile`.
4. **scripts/ directory** — `scripts/*`, `bin/*`, repo-provided runners.
5. **docs / CI** — README/CONTRIBUTING "how to run/deploy", `.github/workflows/*` (mirror exactly what CI does).
6. **Manual fallback** — only when *none* of the above covers it, and **say so explicitly**.

## Hard rules

- **Inspect before you run.** Before any build / deploy / run / release / serve / migrate command, look
  for a Makefile and read its targets. Prefer a matching target to a hand-written command.
- **Dev deploy/build → `make up-dev`** whenever that target exists.
- **Never run these manual commands before checking the Makefile** (use the repo's target/script instead):
  `serverless` / `sls deploy`, `gradle` / `./gradlew`, `npm run build` / `ng build`, `npx cap sync` /
  `cap sync`, `aws … deploy` / `cdk deploy` / `sam deploy`.
- **On a Makefile-target failure: STOP and report.** Show the exact command + its output and ask for
  approval. **Do NOT improvise another deploy/build path** (a different tool, a manual sequence) on your own.
- **Don't invent.** If no automation covers what you need, ask — never guess a deploy command.

## How to discover automation (fast, read-only)

```bash
ls Makefile makefile GNUmakefile 2>/dev/null && grep -E '^[a-zA-Z0-9_.-]+:([^=]|$)' Makefile   # targets
# (or: make help / make -qp | awk -F: '/^[a-zA-Z0-9][^$#\/\t=]*:/{print $1}')
[ -f package.json ]  && grep -A40 '"scripts"' package.json
[ -f composer.json ] && grep -A20 '"scripts"' composer.json
ls scripts/ bin/ Taskfile.yml Justfile 2>/dev/null
```

Reviewers & QA: **flag any manual build/deploy/run command used when an equivalent Makefile target or
repo script exists** — the repo automation should have been used.
