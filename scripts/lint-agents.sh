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
OPUS="architect code-reviewer security-reviewer product-manager ui-ux-engineer root-cause-analyst code-archaeologist pattern-matcher systems-thinker adversarial-tester"
# Throughput agents pinned model: sonnet — the cost floor can't silently regress back to Opus/inherit.
SONNET="backend-engineer frontend-engineer mobile-engineer data-engineer devops-engineer qa-engineer diagrams technical-writer"
# Builders that MUST carry the two context7 doc tools for grounding (every builder except diagrams).
CONTEXT7_BUILDERS="backend-engineer frontend-engineer mobile-engineer data-engineer devops-engineer qa-engineer"
C7_RESOLVE="mcp__plugin_context7_context7__resolve-library-id"
C7_DOCS="mcp__plugin_context7_context7__query-docs"

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

  # 4. builders restricted to a safe set (Read/Grep/Glob/Bash/Write/Edit) plus the two context7 doc
  #    tools (for grounding) — no web/notebook/toolsearch/fan-out, and no OTHER mcp tools.
  case " $BUILDERS " in *" $base "*)
    printf '%s' "$tools" | grep -qwE 'WebFetch|WebSearch|NotebookEdit|ToolSearch' && err "$base: builder has a disallowed tool (web/notebook/toolsearch)"
    rest="$(printf '%s' "$tools" | sed -e "s/$C7_RESOLVE//g" -e "s/$C7_DOCS//g")"
    printf '%s' "$rest" | grep -q 'mcp__' && err "$base: builder may only carry context7 mcp tools (resolve-library-id + query-docs)" ;;
  esac

  # 4b. the six engineering builders MUST carry context7 (grounding can't silently regress to "guess APIs")
  case " $CONTEXT7_BUILDERS " in *" $base "*)
    printf '%s' "$tools" | grep -q "$C7_RESOLVE" || err "$base: builder must carry context7 $C7_RESOLVE (grounding)"
    printf '%s' "$tools" | grep -q "$C7_DOCS" || err "$base: builder must carry context7 $C7_DOCS (grounding)" ;;
  esac

  # 5. model pins — judgment/review/diagnosis stay Opus; throughput stays Sonnet (both directions locked).
  case " $OPUS " in *" $base "*) [ "$model" = "opus" ] || err "$base: should be 'model: opus' (judgment/review/diagnosis role)" ;; esac
  case " $SONNET " in *" $base "*) [ "$model" = "sonnet" ] || err "$base: should be 'model: sonnet' (throughput cost floor — escalate to Opus per-dispatch, don't pin up)" ;; esac
  [ "$base" = "fast-ops" ] && { [ "$model" = "haiku" ] || err "fast-ops must be 'model: haiku' (the only low tier)"; }

  # 5b. PRODUCTION-GRADE MODEL FLOOR (Parallel Orchestration v2): only fast-ops may run on Haiku — no
  #     substantive agent is ever pinned below the Sonnet+ floor. Cost-savings come above the floor.
  [ "$model" = "haiku" ] && [ "$base" != "fast-ops" ] && err "$base: only fast-ops may use Haiku — substantive agents stay at the Sonnet+ production-grade floor"

  # 6. behavioral contract: a REPORT section + anti-hallucination/grounding language
  grep -qiE '^## REPORT|REPORT \(' "$f" || err "$base: missing a REPORT section"
  grep -qiE 'ground|never invent|never fake|hallucinat|evidence|real (file|line)|verif' "$f" || err "$base: missing anti-hallucination/grounding language"
done

# 7. exactly one Haiku tier
haikus="$(grep -l '^model: haiku' agents/*.md 2>/dev/null | wc -l | tr -d ' ')"
[ "$haikus" = "1" ] || err "expected exactly 1 Haiku agent (fast-ops), found $haikus"

if [ "$fail" = 0 ]; then echo "  ALL AGENTS PASS"; else echo "  AGENT LINT FAILED"; fi
exit "$fail"
