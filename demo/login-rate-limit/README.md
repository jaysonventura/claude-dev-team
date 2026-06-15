# Demo — rate-limited `login()` (built by the orchestrator)

A small, security-conscious authentication module **produced end-to-end by claude-dev-team's
orchestration flow** as a worked example of a T2 (squad) task. Pure **Python 3.9, standard library
only** — no third-party dependencies.

## Run it

```bash
python3 -m unittest discover -s demo/login-rate-limit/tests -t demo/login-rate-limit
# Ran 20 tests ... OK
```

## What it does

| File | Responsibility |
|------|----------------|
| `auth/rate_limit.py` | `RateLimiter` — in-memory sliding window with an **injectable clock** (deterministic tests, no real sleeping). `check(key)` records + allows/denies. |
| `auth/login.py` | `AuthService.login(username, password, ip) -> LoginResult` with reasons `OK` / `BAD_CREDENTIALS` / `RATE_LIMITED`. PBKDF2-HMAC-SHA256 hashing, constant-time verify, anti-enumeration. |
| `tests/test_login.py` | 20 unit tests written **to the contract** (success, wrong-password, unknown-user, lockout, window reset via fake clock, no-validity-leak). |

## Security properties

- **PBKDF2-HMAC-SHA256 @ 600,000 iterations** (OWASP-aligned default), per-user salt from `secrets.token_bytes(16)`.
- **Constant-time** password comparison via `hmac.compare_digest`.
- **No user enumeration** — unknown users run a dummy PBKDF2 so timing/branching matches a real user, and return the *same* `BAD_CREDENTIALS` reason as a wrong password.
- **Rate limiting keyed on `username|ip`**, checked **before** any password work; a correct password while locked still returns `RATE_LIMITED` (no validity leak). The counter resets on a verified-correct login.

## How it was built (the point of the demo)

The orchestrator ran this as a **T2 squad** (auth → risk floor):

1. **architect** — designed the interface + an 8-point security checklist + per-agent contracts.
2. **backend-engineer ∥ qa-engineer** (parallel) — implementation and 20 contract tests written at the same time. The qa pass **caught two real backend defects** (an iteration floor that broke the contract, and a rate limiter mistakenly keyed on `ip` alone instead of `username|ip`).
3. **Task Loop** — a focused fix dispatch corrected both → 20/20 green.
4. **code-reviewer ∥ security-reviewer** — independent review; security cleared with no veto.

### Known low-severity advisories (intentionally left as exercises)

- The unknown-user dummy PBKDF2 is pinned at the default iteration count; a faint timing oracle appears only if credentials are stored at *non-default* iteration counts.
- `RateLimiter` has no idle-key eviction — unbounded memory growth under very high-cardinality `username|ip` traffic. Add a periodic sweep or LRU cap for production.

> This is illustrative example code, not a drop-in auth library.
