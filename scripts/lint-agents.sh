#!/usr/bin/env bash
# scripts/lint-agents.sh — static conformance + least-privilege lint for every agents/*.md.
# Locks in the security hardening so it can't silently regress. Exits non-zero on any violation.
# Runs in CI alongside validate.sh. Pure shell — no model, deterministic.
set -u
cd "$(dirname "$0")/.." || exit 1
fail=0
err() { echo "  FAIL: $*"; fail=1; }

# Agent classes (basenames without .md)
READONLY="architect code-reviewer security-reviewer product-manager root-cause-analyst code-archaeologist pattern-matcher systems-thinker adversarial-tester"
BUILDERS="backend-engineer frontend-engineer mobile-engineer data-engineer devops-engineer qa-engineer diagrams"
OPUS="architect code-reviewer security-reviewer product-manager ui-ux-engineer"

echo "== agent lint (conformance + least-privilege) =="
for f in agents/*.md; do
  base="$(basename "$f" .md)"
  tools="$(grep -m1 '^tools:' "$f" 2>/dev/null | cut -d: -f2-)"
  model="$(grep -m1 '^model:' "$f" 2>/dev/null | cut -d: -f2- | tr -d ' ')"

  # 1. required frontmatter (no implicit "ALL tools")
  grep -q '^name:' "$f" || err "$base: missing name"
  grep -q '^description:' "$f" || err "$base: missing description"
  [ -n "$tools" ] || err "$base: missing explicit 'tools:' line (would default to ALL tools)"

  # 2. NO agent may fan out — only the orchestrator dispatches subagents
  printf '%s' "$tools" | grep -qwE 'Task|Agent' && err "$base: must not carry Task/Agent (no fan-out)"

  # 3. read-only agents must not be able to write
  case " $READONLY " in *" $base "*)
    printf '%s' "$tools" | grep -qwE 'Write|Edit|NotebookEdit' && err "$base: read-only agent must not have Write/Edit" ;;
  esac

  # 4. builders restricted to a safe set (Read/Grep/Glob/Bash/Write/Edit) — no web/notebook/mcp/fan-out
  case " $BUILDERS " in *" $base "*)
    printf '%s' "$tools" | grep -qwE 'WebFetch|WebSearch|NotebookEdit|ToolSearch' && err "$base: builder has a disallowed tool (web/notebook/toolsearch)"
    printf '%s' "$tools" | grep -q 'mcp__' && err "$base: builder should not carry mcp tools" ;;
  esac

  # 5. model pins
  case " $OPUS " in *" $base "*) [ "$model" = "opus" ] || err "$base: should be 'model: opus' (judgment role)" ;; esac
  [ "$base" = "fast-ops" ] && { [ "$model" = "haiku" ] || err "fast-ops must be 'model: haiku' (the only low tier)"; }

  # 6. behavioral contract: a REPORT section + anti-hallucination/grounding language
  grep -qiE '^## REPORT|REPORT \(' "$f" || err "$base: missing a REPORT section"
  grep -qiE 'ground|never invent|never fake|hallucinat|evidence|real (file|line)|verif' "$f" || err "$base: missing anti-hallucination/grounding language"
done

# 7. exactly one Haiku tier
haikus="$(grep -l '^model: haiku' agents/*.md 2>/dev/null | wc -l | tr -d ' ')"
[ "$haikus" = "1" ] || err "expected exactly 1 Haiku agent (fast-ops), found $haikus"

if [ "$fail" = 0 ]; then echo "  ALL AGENTS PASS"; else echo "  AGENT LINT FAILED"; fi
exit "$fail"
