#!/usr/bin/env bash
# cdt-route "<subtask>" — advisory model recommendation for a dispatch, under the PRODUCTION-GRADE FLOOR:
#   Opus   — judgment / review / security / architecture / risk-flagged work
#   Sonnet — substantive build / test / throughput (production-grade default)
#   Haiku  — ONLY trivial, zero-judgment mechanical ops (fast-ops); NEVER substantive code
# Advisory (like cdt-advise / cdt-auto explain); the orchestrator decides. Pure stdlib python3; fail-open.
set +e

TASK="$*"
[ -z "$TASK" ] && { echo "usage: cdt-route \"<subtask description>\""; exit 0; }
command -v python3 >/dev/null 2>&1 || { echo "sonnet  (cdt-route needs python3 to classify — defaulting to the Sonnet production-grade floor)"; exit 0; }

TASK="$TASK" python3 - <<'PY'
import os
t = " " + os.environ["TASK"].lower() + " "
def has(words): return any(w in t for w in words)

RISK = ["auth", "login", "password", "oauth", "token", "payment", "billing", "stripe", "secret",
        "credential", "crypto", "encrypt", "infra", "terraform", "kubernetes", "migration", "rbac",
        "permission", "security", "vulnerab", "injection", " xss", "csrf"]
HARD = ["architect", "design ", "redesign", "refactor", "ambiguous", "tricky", "complex", "concurrency",
        "race condition", "deadlock", "distributed", "algorithm", "optimi", "performance", "root cause",
        "debug", "review", "audit", "tradeoff", "decide", "strategy", "api design", "data model"]
TRIVIAL = ["rename", "typo", "whitespace", "reformat", "format ", "prettier", "lint fix", "sort import",
           "add a comment", "bump version", "reword", "copy ", "move file", "find and replace",
           "find/replace", "rename variable", "fix indentation", "spelling"]

if has(TRIVIAL) and not (has(RISK) or has(HARD)):
    print("haiku   trivial mechanical op — fast-ops/Haiku OK (zero judgment). NEVER for substantive code.")
elif has(RISK):
    print("opus    risk-flagged (auth/payments/infra/migration/security) — use Opus (production floor + judgment).")
elif has(HARD):
    print("opus    judgment/design/review work — use Opus (ambiguity, architecture, perf, or hard debug).")
else:
    print("sonnet  substantive build/test/throughput — Sonnet is production-grade and sufficient here.")
PY
exit 0
