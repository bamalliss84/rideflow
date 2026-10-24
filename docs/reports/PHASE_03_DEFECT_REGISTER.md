# Phase 3: defect register

Scope: the existing Phase 1 backend and Phase 2 admin portal. Every fixed defect has a regression test that failed before the fix (or would have) and passes after it.

## Defects

| ID | Severity | Area | Status |
|---|---|---|---|
| P3-01 | High | Security: rate limiting | Fixed |
| P3-02 | High | Security: production configuration | Fixed |
| P3-03 | Medium | Security / reliability: production configuration | Fixed |
| P3-04 | Medium | Reliability | Fixed |
| P3-05 | Medium | Performance | Fixed |
| P3-06 | Low | Security hardening | Fixed |
| P3-07 | Low (not exploitable) | Defence in depth | Hardened |
| P3-08 | Low (local only) | Secret hygiene | Fixed |

### P3-01: per-IP throttles could be evaded with a forged `X-Forwarded-For`; platform password login could be brute-forced

- **Reproduction:**
  - The API trusted the whole client-supplied `X-Forwarded-For`: DRF `NUM_PROXIES` was unset.
  - The BFF forwarded the client's first XFF entry, and Next.js only sets XFF when the client did not send one.
  - Rotating the header therefore gave every request a new per-IP throttle bucket, for OTP request/verify (IP layer), MFA (IP) and platform login.
  - Platform password login had **only** that per-IP limit.
- **Expected:** a client cannot choose its own throttle identity, and password login is limited per account.
- **Root cause:** an implicit trust of proxy headers, and a missing per-account limit on platform login.
- **Fix:**
  - `REST_FRAMEWORK["NUM_PROXIES"]` comes from `TRUSTED_PROXY_COUNT` (default 0: `REMOTE_ADDR` only).
  - The BFF forwards only the entry appended by its own trusted proxy (`TRUSTED_PROXY_COUNT`, default 0 = forward nothing).
  - Platform login is throttled per phone (`platform_login`, 10/h) **and** per IP (`platform_login_ip`, 30/h).
- **Files:** `services/api/rideflow/settings.py`, `apps/accounts/views.py`, `apps/admin/src/lib/server/session.ts`, `docker-compose.yml`, `.env.example`.
- **Regression tests:** `test_spoofed_forwarded_for_cannot_evade_ip_throttles`, `test_platform_login_is_throttled_per_account_across_ips`.
- **Live evidence:** repeated UI logins with the same phone are refused through the BFF with "Too many attempts" (seen during the E2E runs).

### P3-02: production accepted a weak or placeholder `DJANGO_SECRET_KEY`

- **Reproduction:** `DJANGO_DEBUG=0` with `DJANGO_SECRET_KEY=short` or the documented dev placeholder started normally. JWT signing and the derived MFA key depend on it.
- **Fix:** with DEBUG off, the API refuses keys shorter than 50 characters or with the `dev-only-insecure`/`django-insecure` prefix.
- **Test:** `test_production_settings_refuse_weak_secrets` (two cases).

### P3-03: production silently derived `MFA_ENCRYPTION_KEY` from `SECRET_KEY`

- **Risk:** rotating `SECRET_KEY` would make every enrolled authenticator undecryptable, locking out all administrators.
- **Fix:** `MFA_ENCRYPTION_KEY` is required when DEBUG is off; generation is documented in `.env.example`.
- **Test:** `test_production_settings_refuse_weak_secrets[MFA_ENCRYPTION_KEY]`.

### P3-04: a Redis outage returned an opaque 500 after about 4 s

- **Reproduction:** `docker compose stop redis`, then `POST /api/v1/auth/otp/request` returned 500 (dev: an HTML debug page).
- **Expected:** a retryable, non-revealing error.
- **Fix:** the API exception handler maps Redis connection/timeout errors to `503 {"code":"service_unavailable"}` with `Retry-After: 5`.
- **Test:** `test_redis_outage_returns_503_with_retry_after`.
- **Live verification:** 503 plus `Retry-After: 5` during the outage; readiness back to 200 two seconds after Redis restarted, with no API restart needed.

### P3-05: N+1 queries in four admin lists

- **Reproduction:** with about 10 extra rows, query counts grew per row:

  | List | Queries before → after adding rows |
  |---|---|
  | `admin/audit-events` | 19 → 29 |
  | `admin/driver-documents` | 11 → 41 |
  | `admin/subscriptions` | 12 → 32 |
  | `admin/vehicles` | 10 → 30 |

- **Root cause:** `name_field("driver.user.full_name")` / `actor.full_name` without `select_related`.
- **Fix:** `select_related("driver__user", "vehicle")`, `select_related("driver__user")`, `select_related("plan", "driver__user")`, `select_related("actor")`.
- **Guard test:** `test_admin_list_endpoints_have_no_n_plus_one`. It covers every tenant `admin-*-list` route and fails if the count grows by more than 2.

### P3-06: no HSTS in production; OpenAPI schema and Swagger public in production

- **Fix:**
  - `SECURE_HSTS_SECONDS` defaults to 1 year when DEBUG is off.
  - `SECURE_SSL_REDIRECT` is opt-in (TLS is normally terminated at the proxy; `/health/` is exempt).
  - `API_DOCS_ENABLED` defaults to DEBUG.
- **Tests:** `test_api_docs_are_disabled_unless_enabled`, and the production-settings test asserts HSTS, secure cookies and docs off.

### P3-07: BFF proxy accepted dot path segments (hardening)

- **Finding:** `%2e`/`%2e%2e` segments could in principle leave `/api/v1` after `fetch` normalisation.
- **Not exploitable today:** live probes returned 404 because Next.js normalises before routing.
- **Change:** the proxy now rejects `.`, `..` and empty segments explicitly.

### P3-08: the admin Docker build context included the E2E folder (saved session cookies)

- **Finding:** `apps/admin/.dockerignore` did not exclude `e2e/`, so `e2e/.auth/*.json` (local test-account cookies) could be copied into locally built admin images.
- **Fix:** `e2e` and `playwright.config.ts` are excluded from the Docker context.
- **Residual risk:** local only, dev-bypass test accounts, tokens expire within 12 h. Rebuilding the image removes them.

## E2E harness issues found while building the suite (test code only, not product defects)

- Refresh tokens are single-use (rotation plus blacklist). Reused saved sessions must be rotated at setup, so the harness always rotates them.
- The per-phone OTP limit (5/h) blocked repeated UI-login runs. The suite now rotates six dedicated login-test owners every 10 minutes. This also confirms the limit works through the BFF.

## Reviewed, no defect found (evidence in the QA report)

- **Cross-tenant IDOR:** PATCH/PUT/DELETE and well-formed action bodies against tenant A ids from a tenant B owner session: 0 successes, no data leaks, tenant A records unchanged.
- **Refresh token reuse after rotation:** refused (401).
- **Tokens:** tampered or signature-stripped tokens refused; a token with a foreign tenant's app header is refused.
- **Pagination:** capped at 100.
- **Headers:** `X-Frame-Options: DENY` and `nosniff` on the API.
- **CSRF:** enforced on BFF mutations (403 without the header).
- **Cookies:** session cookies are HttpOnly and SameSite=Strict.
- **Portal separation:** a platform session cannot open operator pages or APIs (redirect / 403); an operator session gets 403 on platform APIs.
- **Read-only roles:** reviewer cannot write policy (403); support cannot open members (403).
