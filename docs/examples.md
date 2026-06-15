# Extended examples

Walkthroughs of how the orchestrator handles tasks at each tier. These are illustrative — your real
runs adapt to the project.

## T0 — trivial (solo)

> **You:** fix the broken link in `README.md`.

Triage: 1 file, 1 domain, no risk → **T0**. The orchestrator edits directly, runs nothing heavier than a
quick check, and ships. No team, no Discord spam (INFO is below the default notify level). ~1 call.

## T1 — small single-domain

> **You:** add a `formatCurrency` helper and use it in the cart total.

Triage: 1–2 files, 1 domain → **T1**. The orchestrator (optionally with one builder) implements, adds a
unit test, runs the test, and ships with a light close (verify + simplify-if-touched).

## T2 — multi-domain / risk floor (squad)

> **You:** add a rate-limited `POST /login` endpoint with tests.

`auth` trips the **risk floor** → **T2+**.
1. **Wave 0:** `architect` defines the request/response types, the rate-limit strategy, and the file plan.
2. **Wave 1 (parallel):** `backend-engineer` implements `api/auth/*`; `qa-engineer` writes `test/auth/*`.
3. **Gates + Task Loop:** types → lint → unit → integration. A failing test triggers a focused fix; loop
   until green or the cap.
4. **Wave 2:** `code-reviewer` checks scope/correctness; `security-reviewer` traces the auth path and the
   limiter (veto if weak).
5. **Mandate + ship:** simplify, reuse-audit, dead-code scan, write a vault learning, then
   `cdt-notify SHIP "/login shipped: rate-limited, N tests green"`.

## T3 — large / cross-cutting (full team)

> **You:** build a settings page on web and mobile, backed by a new API and a DB migration.

Triage: multiple domains + a migration (risk) → **T3**.
- **Wave 0:** `architect` + `Explore` map the surface and define shared contracts; `diagrams` sketches the
  data flow.
- **Wave 1 (parallel, exclusive paths):** `data-engineer` (`db/*`, reversible migration) ·
  `backend-engineer` (`api/settings/*`) · `frontend-engineer` (`ui/settings/*`) ·
  `mobile-engineer` (`mobile/settings/*`) · `qa-engineer` (`test/*`).
- **Gates + Task Loop**, then **Wave 2** review (security checks the migration + endpoints).
- **Full mandate + ship**, with per-milestone Discord/Telegram posts and a `vault/sessions/` entry.

## When a bug gets stuck

If the Task Loop sees the same gate fail with the same signature twice, it convenes the **Bug Council**:
five read-only diagnosticians run in parallel, the orchestrator synthesizes one ranked root cause + fix
plan, an engineer implements, and the verdict is posted. You can also trigger it manually:

> **You:** `/cdt:bug-council the checkout total is off by one cent intermittently`

## Conserving Max limits

- Run routine work in a **Sonnet session**; reach for `/model opus` + `FULL:` only when it matters.
- Prefix a quick change with `T0:` to force solo mode.
- Watch spend with `/cdt:stats week` and rebalance.
