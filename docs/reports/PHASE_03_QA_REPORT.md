# Phase 3: QA and security hardening report

| | |
|---|---|
| Date | 2026-10-24/25 |
| Environment | Windows 11, Docker Desktop 4.96.1 (WSL2), local stack: PostGIS, Redis, API (Django dev `runserver`/daphne, DEBUG=1), admin (Next.js production build), Chrome stable for Playwright |
| Baseline commit | `25098a6` (CI green, verified via the GitHub Actions API) |
| Final commit | `c934039` |

**Status words:**
- **PASSED:** executed and verified.
- **FAILED:** executed and failed.
- **BLOCKED:** could not execute (reason given).
- **NOT TESTED:** outside verified coverage.

## 1. Baseline (A)

| Check | Command | Result |
|---|---|---|
| Git | `git status -sb` | clean, `main...origin/main` at `25098a6` |
| GitHub Actions | `GET api.github.com/repos/bamalliss84/rideflow/actions/runs` (no `gh` CLI on this machine) | PASSED: last 5 runs `success`, latest `25098a6` |
| Services | `docker compose ps` | db, redis, api, worker, admin up/healthy |
| Migrations | `manage.py makemigrations --check --dry-run`; `showmigrations` | no changes; 0 unapplied |
| Contract | `manage.py spectacular --validate --fail-on-warn` diffed with `packages/contracts/openapi.yaml` | identical |
| Deploy check | `manage.py check --deploy` (dev stack) | 6 warnings, expected with DEBUG=1. Production gaps found here led to P3-02/03/06. |

## 2. Defects fixed

Details are in [PHASE_03_DEFECT_REGISTER.md](PHASE_03_DEFECT_REGISTER.md).

| ID | Severity | Summary |
|---|---|---|
| P3-01 | High | Forged `X-Forwarded-For` evaded per-IP throttles; platform password login brute-forceable |
| P3-02 | High | Production accepted weak or placeholder `SECRET_KEY` |
| P3-03 | Medium | Production derived the MFA encryption key from `SECRET_KEY` |
| P3-04 | Medium | Redis outage returned 500 instead of a retryable 503 |
| P3-05 | Medium | N+1 queries in 4 admin lists |
| P3-06 | Low | No HSTS / public API docs in production |
| P3-07 | Low | Proxy dot-segment guard (hardening, not exploitable) |
| P3-08 | Low | E2E session files in the admin Docker build context |

No critical defect was found. No business rule, state machine, policy default or approval status was changed.

## 3. New feature: administrator MFA recovery codes (G)

**Behaviour:**
- **Generation:** `GET/POST /api/v1/auth/mfa/recovery-codes` creates 10 one-time codes `xxxxx-xxxxx` (40 random bits each).
- **Storage:** only an HMAC-SHA256 keyed with the MFA key (or derived in dev) is stored, unique per user and code.
- **Who can manage codes:** only sessions that passed the real second factor (`mfa` claim; dev-bypass sessions are refused). Regenerating needs a fresh, non-replayed authenticator code and invalidates the previous set. Audit event `auth.mfa_recovery_codes_generated`.
- **Use at sign-in:** a code replaces the authenticator code at `POST /auth/mfa/verify` (`recovery_code`, exactly one of `code`/`recovery_code`). It is redeemable only against a valid signed challenge, so the first factor (OTP or password) is always required.
- **Consumption:** atomic (single `UPDATE … WHERE used_at IS NULL`). Counts toward the existing 5-attempts-per-challenge limit; a 6th attempt is refused even with a valid code, and that code is not consumed.
- **Audit and status:** login audit records `recovery_code` and the remaining count; `/me` exposes `mfa.recovery_codes_remaining`.

**Portal:**
- The MFA step has "Use a recovery code".
- The account page shows remaining codes, generates or regenerates after an authenticator code, and shows the codes once with copy and `.txt` download.

**Tests:** `tests/test_mfa_recovery.py` (5 tests) covers generation guard and fresh-code requirement, hashing, single use, reuse refusal, regeneration invalidation, brute-force bound, user binding and platform scope. E2E: a dev-bypass session cannot manage codes (UI hidden, BFF/API 403).

Migration `accounts.0004_mfa_recovery_codes` is additive.

## 4. Automated tests: commands and counts

### 4.1 Backend: PASSED

`docker compose exec -T api python -m pytest --create-db -p no:logging` gives **144 passed in 185 s** (baseline 126, plus 18 new).

**`tests/test_phase3_security.py`** (14 tests):
- cross-tenant PATCH/PUT/DELETE and well-formed action bodies on every parameterised route: ≥200 probes, all 400/403/404/405, no leaks, tenant A unchanged;
- refresh-token reuse after rotation;
- tampered tokens and foreign app header;
- page-size cap;
- API security headers;
- API docs gate;
- production-settings refusal (×3) with HSTS and secure cookies;
- XFF throttle evasion;
- per-account platform-login throttle;
- N+1 guard over all admin lists;
- Redis-outage 503.

**`tests/test_mfa_recovery.py`:** 5 tests. Existing `/me` assertion updated for the new field.

**Other checks:**

| Check | Result |
|---|---|
| `ruff check .` and `ruff format --check .` | PASSED |
| `makemigrations --check` | PASSED |
| OpenAPI `--validate --fail-on-warn` | PASSED; contract regenerated for the recovery-code endpoint and notification changes |

### 4.2 Frontend static checks: PASSED

| Check | Result |
|---|---|
| `npx tsc --noEmit` | 0 errors |
| `npx eslint . --max-warnings=0` | 0 findings (includes the E2E code) |
| Production build | PASSED, built in Docker several times during the session |

The final rebuild after the last commits is BLOCKED (see §9). CI runs `npm run build` on push.

### 4.3 Playwright E2E: PASSED, with the final re-run BLOCKED

**How it runs:**
- Command: `cd apps/admin && npx playwright test` (one worker, local Chrome, against the running stack).
- Data: the dedicated `e2e-qa` tenant (`manage.py seed_e2e`, DEBUG-only). Workflow records are created per run through the public API with fresh phone numbers. Owner demo data is untouched.

**25 tests in 4 files:**

| File | Coverage |
|---|---|
| `auth.spec.ts` (8) | UI login with dev OTP (no TOTP); `/api/auth/session` shows backend-authorised `dev_bypass`; logout; protected-route redirect; wrong OTP; transparent session renewal with refresh rotation (HttpOnly/SameSite=Strict asserted); CSRF refusal; support role denied members (UI + 403); platform password login, operator deep link redirected, operator API 403; operator session gets 403 on platform API; direct API refuses missing or forged tokens |
| `workflows.spec.ts` (4) | Driver application through the driver API, then reviewer UI: premature approval refused and explained, 3 documents + vehicle approved, driver approved (backend state checked). Document rejection requires a reason. Deposit receipt through the driver API, finance UI approval, subscription entitled, second approval 409, exactly one ledger row with the plan amount. Completed cash ride over the public ride API, rider dispute, reviewer notification (unread), deep link to the case, resolution with a recorded violation (backend checked) |
| `settings-reports.spec.ts` (6) | Policy: range validation, unsaved bar, `beforeunload` prompt, new version saved with a note, value persisted, version number +1, history entry. Reviewer read-only policy (no editors, API 403). Reports: 7-day range, chart, KPI equals the server rows sum, CSV filename, header and row count match server rows. Error, retry and recovery with loading skeleton; filtered empty state; failed mutation shows an inline error (no fake success); dev-bypass session cannot manage recovery codes |
| `layout-i18n.spec.ts` (7) | Arabic RTL by default, English LTR switch and back; no page-level horizontal overflow on 11 operator routes at 375, 768, 1280 and 1440 px; mobile drawer navigation; modal focus containment and Escape |

**Runs:**
- Full runs passed **24/25**. The only failure was the UI-login test hitting the per-phone OTP limit (5/h) after repeated runs. That is correct product behaviour, and the harness now rotates dedicated login phones.
- The re-run of `auth.spec.ts` after the change gave **8/8 PASSED**.
- Every spec file has passed in full on the current product code.
- **BLOCKED:** one final end-to-end run after the last commits (Docker engine down, §9). Changes after the last full run: harness phone rotation; the lost-authenticator text; backend `select_related` and 503 mapping (covered by the backend suite); `.dockerignore`.

## 5. Security and tenant-isolation evidence (D)

| Area | Evidence | Status |
|---|---|---|
| Cross-tenant reads, lists, search, objects | Existing generated route test (GET/POST on every route) + RLS / fail-closed ORM / composite FK tests | PASSED |
| Cross-tenant writes with valid bodies, PATCH/PUT/DELETE | New `test_mutating_verbs_and_valid_bodies…` | PASSED |
| Exports | CSV is built only from tenant-scoped API data; E2E checks row parity | PASSED |
| Platform vs operator separation | Backend tests + E2E (redirects, 403 both ways) | PASSED |
| Forged tenant/app headers, token tampering | Existing + new tests | PASSED |
| RBAC escalation / IDOR | Role matrix (existing), support/reviewer E2E, maker-checker and own-case tests (existing) | PASSED |
| MFA enforcement and dev-bypass boundaries | D033 tests (bypass refused outside DEBUG + local + local hosts; disabling the flag revokes sessions); settings refuse the flag in production | PASSED. Production itself NOT TESTED (no production environment) |
| Sessions: expiry, rotation, revocation, CSRF | Backend + E2E | PASSED |
| Uploads and private media | Existing tests (disguised/oversized files, tenant-namespaced storage); no media URL routed | PASSED |
| Rate limiting | OTP per phone/IP, MFA attempts, platform login per account + IP (P3-01) | PASSED |
| Sensitive data and headers | API `X-Frame-Options`/`nosniff`; admin CSP and headers (existing config); API docs hidden in production (P3-06) | PASSED |
| Audit immutability | Existing append-only tests | PASSED |
| Race conditions | Existing concurrency suite (offer selection, duplicate approvals, driver confirmation, idempotency) in the 144 | PASSED |
| WebSocket authorization and tenant namespacing | Existing realtime tests | PASSED |
| Malware scanning of uploads | No scanner integrated | NOT TESTED (release blocker) |

## 6. Performance and reliability measurements (E)

### Single requests, in process

Measured in the API container with `CaptureQueriesContext`, on the e2e tenant:

| Endpoint | Time | Queries |
|---|---|---|
| `admin/drivers` (25/page) | 75 ms | 10 |
| `admin/dashboard` | 198 ms | 24 |
| `/me` | 57 ms | 7 |

### Bounded load

Command: `python scripts/perf_smoke.py`. 120 requests per endpoint, concurrency 10, against `127.0.0.1:8010`, 720 requests in total, **0 errors**.

| Endpoint | p50 | p95 | max | req/s |
|---|---|---|---|---|
| GET /health/ready | 332 ms | 651 ms | 695 ms | 27.4 |
| GET /me (rider) | 582 | 1059 | 1223 | 15.8 |
| POST /fare-estimate | 604 | 1084 | 1160 | 15.2 |
| GET /admin/drivers | 2597 | 2977 | 3132 | 4.0 |
| GET /admin/dashboard | 1741 | 2143 | 2611 | 5.8 |
| GET /admin/audit-events | 899 | 1344 | 1442 | 10.7 |

**Interpretation:**
- Throughput is bounded by the development server. `runserver` with DEBUG runs sync views on one thread, so requests queue (≈ concurrency × single-request time).
- These numbers are **not** production capacity.
- A production ASGI server with several workers is not yet defined (release blocker R-01).
- Using `localhost` instead of `127.0.0.1` on Windows added about 200 ms per connection (IPv6 fallback); the script uses IPv4.

### Query efficiency

Four N+1 defects were fixed (P3-05). A guard test now covers every admin list.

### Reliability

| Scenario | Result |
|---|---|
| Redis stopped | readiness 503, liveness 200, API returns 503 + `Retry-After` (P3-04) |
| Redis restarted | ready again in 2 s, no API restart |
| WebSocket reconnect / resume replay | existing realtime tests pass |
| Expired access token | E2E renewal passes |
| Transient 500 / network failure in the UI | E2E error, retry and inline-error tests pass |
| Repeated submissions | existing idempotency tests; UI buttons disable while busy |

## 7. Browser and viewport coverage (F)

**Covered:**
- Chrome (stable, desktop engine) at 375, 768, 1280 and 1440 px.
- Arabic RTL and English LTR.
- Mobile drawer.
- Keyboard and Escape in dialogs.
- No page-level overflow on 11 key routes at all four widths.
- The Phase 2 manual review covered all 24 operator routes at 375 px.

**NOT TESTED:**
- Firefox, Safari/WebKit, and real mobile devices.
- Screen-reader output (only labels and roles asserted).

## 8. GitHub Actions

| Commit | Result |
|---|---|
| Baseline `25098a6` | success (verified via API) |
| Phase 3 commit | verified after push; see the project state and the final message |

The E2E suite is not part of CI: it needs the full stack plus a browser. It is documented as a local release gate.

## 9. Environment blocker during final verification

During the final `docker compose up -d --build`, **drive C: reached 100% (26 MB free)**. Docker Desktop's WSL engine crashed (`signal: bus error`, `docker-desktop Stopped`, "Docker Desktop is unable to start").

Nothing in the repository or database was affected: named volumes live in the Docker disk and were not deleted. I did not delete any of the owner's files to free space.

Owner action:

1. Free space on C: with Windows Disk Cleanup or by moving large files. Do **not** use Docker Desktop's "Clean / Purge data": it deletes the database volume.
2. Start Docker Desktop.
3. Run `docker compose up -d --build`.

After that, still to run:
- the last full E2E run;
- the final Docker production build of the admin image.

## 10. Remaining risks and external blockers

See [PHASE_03_RELEASE_READINESS.md](PHASE_03_RELEASE_READINESS.md).

## 11. Decision

**CONDITIONAL PASS.**

**Why it passes:**
- No unresolved critical or high defect.
- 8 defects fixed with regression tests.
- The backend suite (144) and static frontend checks pass.
- The 25-test E2E suite passed on the product code.
- MFA recovery is implemented without weakening the first factor.

**Conditions:**
1. Re-run the full E2E suite and production build once Docker is restored (blocked by host disk space).
2. Confirm CI is green for the Phase 3 commit.
3. Address the release blockers before any production or pilot launch: production ASGI server, malware scanning, SMS provider, real maps, legal approvals, owner-approved policy values, trusted-proxy configuration.

The baseline is ready for the separate Phase 4 Flutter driver-app work, which talks only to the tested API.
