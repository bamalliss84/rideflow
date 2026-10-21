# Phase 1 — Backend Report

| | |
|---|---|
| Date | 2026-10-21 |
| Branch | `main` |
| Implementation commit | `<PHASE1_COMMIT_SHA>` |
| Environment | Native Windows 11 host; Docker Desktop 4.96.1 (Engine 29.9.2, Compose v5.6.0); containers python:3.12-slim, postgis/postgis:16-3.4, redis:7.4-alpine |
| Status | **Backend implemented and validated locally. Phase 1 is NOT declared complete** because of the open items in §3 (admin MFA, production adapters, and CI not yet observed green on GitHub at the time of writing). |

## 1. Summary

The Django modular backend covers all 11 Phase 1 deliverable areas:

- multi-tenant foundation and isolation
- authentication and driver onboarding
- geo and dispatch
- ride lifecycle with bidding
- subscriptions
- trust and conduct
- real time
- platform and tenant admin APIs
- reports

It runs locally with Docker Compose. Every check below was actually executed: 103 automated tests, lint, format, migration consistency, OpenAPI validation and a live HTTP smoke test. All passed.

## 2. Completed items (by deliverable)

| # | Deliverable | Delivered |
|---|---|---|
| 1 | Repository foundation | `README.md`, `.gitignore`, `.gitattributes`, `.env.example`, and `docker-compose.yml` (db, redis, api, worker). Also `infra/docker/postgres/init` (non-superuser app role, PostGIS in template1), `scripts/` (`dev-up.ps1`, `test.ps1`, `export-openapi.ps1`, `dev.sh`), `.github/workflows/ci.yml` (gitleaks, lint, format, migrations, tests, OpenAPI drift, Docker smoke), and health endpoints `/health/live` and `/health/ready` (DB + PostGIS + Redis). |
| 2 | Django project, API, docs, data | Modular apps under `services/api/apps`. Versioned `/api/v1`. OpenAPI 3 via drf-spectacular (Swagger, ReDoc, schema), committed to `packages/contracts/openapi.yaml`, which is validated with zero warnings. Initial migrations for 9 apps. Idempotent `seed_demo` with two demo tenants. |
| 3 | Tenancy | Tenant, TenantApplication (white-label app context), TenantMembership with 7 roles, role→permission map, versioned append-only TenantConfig with a validated policy catalogue, and an immutable audit trail. Isolation layers: fail-closed ORM manager, FORCE RLS on all 28 tenant tables, 31 composite FKs, and tenant-namespaced cache, WebSocket and file paths. |
| 4 | Auth, users, drivers | Global users and per-tenant memberships (D022). OTP login through the app context with a dev adapter: HMAC-stored codes, attempt caps, per-phone and per-IP throttles. JWT with the `tid` claim, refresh rotation and blacklist logout. Platform password login. Driver onboarding: vehicles, document upload with magic-byte and size validation, submit, and the admin review queue (approve/reject with reasons). Eligibility covers status, documents not expired, approved vehicle, subscription entitlement, restrictions and tenant status. Drivers can go online and offline. |
| 5 | Geo | City, ServiceArea (polygons) and DriverLocation (geography, GiST). Location updates ignore out-of-order fixes and clamp device clock skew. Nearby search is coarse for riders and detailed for staff. Fare estimate is an indicative range labelled "estimate, not guaranteed". Service-area enforcement. |
| 6 | Rides | Explicit state machine (11 states). Dispatch in staged waves with radius expansion and a cap. Bids have expiry, per-ride and open-bid limits, and withdraw/re-bid. Riders compare offers (price, ETA, trust brief) and select. Driver confirmation is required (D027) with a timeout. Agreed fare is locked, and bilateral amendments are supported. En route, arrive (geofence + accuracy evaluation), contact attempts, start, complete, and cash confirmation by both parties. Cancellation by either side uses a free window, and late cancels are recorded for review. No-show requires wait, geofence and contact evidence. Unmatched requests expire. Row locks, `expected_version`, partial unique indexes and append-only events with a replay cursor. |
| 7 | Subscriptions | Plans, deposit accounts and deposit claims (receipt upload). Per-tenant uniqueness of reference and receipt hash. Amount must match the plan price. Optional maker-checker with distinct approvers; self-approval is blocked. Approval extends the subscription from its current end and writes an append-only ledger. Founder trial (once per driver, capped per tenant). Entitlement checks gate online status and bidding. |
| 8 | Trust | Bilateral ratings (once each, inside a window). Bayesian trust score with separate commitment components and display tiers. Incidents are recorded as pending review, never auto-applied. Enforcement ladder: warning or commitment effect activate automatically; restrictions are proposed and need human activation; safety goes to escalation. Appeals are decided by a different reviewer and overturning revokes enforcement. Disputes with notes and resolution create violations for review, and a no-show contest overturns the no-show. Renewal discount and compensation are implemented but disabled by default. |
| 9 | Real time | Persisted notifications. WebSocket hints at `/ws/v1/events/?token=` in per-user, tenant-namespaced groups, with hello, resume-by-cursor replay and ping/pong. REST replay at `GET /notifications?after=`. Idempotency-Key on all critical mutations, with stored replay and payload-mismatch rejection. |
| 10 | Platform / tenant management | Platform: tenant create/list/update/suspend/activate, app registration, first admin. Platform staff have no tenant data access. Tenant: profile, members (owner rules), config versions, cities and service areas, review queues, deposit queue, ride explorer (filters, events, bids, evidence), violations, enforcement, appeals, disputes, trust snapshots, audit log, dashboard metrics (supply, demand, rates, timings, queues), and daily ride and subscription reports. |
| 11 | Tests and documentation | 103 tests: isolation (including a generated all-route check), permission negatives, business rules, parallel-transaction concurrency, WebSocket. OpenAPI documentation and README. |

## 3. Remaining items (not done, or done only partially)

| Item | Status |
|---|---|
| Admin MFA (R01-04, T13) | **Not implemented.** Tenant staff use OTP and platform staff use a password. Required before any non-local environment. |
| Real OTP/SMS provider, push notifications (FCM/APNs) | Not implemented: no provider is approved. A dev OTP adapter (logs only) exists. Notifications are in-app/WebSocket only. |
| Upload malware scanning, PII encryption at rest, retention jobs (T11, T12, OD-07) | Not implemented. Uploads are validated by type and size and stored privately under tenant paths, served only by authorised endpoints. |
| PostgreSQL RLS for `AuditEvent` | AuditEvent stays out of RLS because platform events have no tenant. API access is filtered by tenant explicitly. |
| Platform break-glass access to tenant data (OD-09) | Not implemented: platform admins have no tenant data endpoints at all. |
| Production deployment config (TLS, gunicorn/uvicorn workers, static, backups/restore drill, staging) | Out of Phase 1 scope; a development stack only. |
| CI on GitHub Actions | Workflow committed. **Its first remote run had not been observed passing at the time of writing.** The identical steps passed locally (§4). |
| Load and field tests, Flutter/Next.js E2E | Later phases. |
| Policy values | Every value marked PROPOSED/PROVISIONAL needs owner approval (D009–D011, D013–D015, OD-02, OD-05–OD-09). |

## 4. Tests and actual results

All commands ran on the Windows host via Docker on 2026-10-21.

| Command | Result |
|---|---|
| `scripts\test.ps1 -PytestArgs "--create-db -rA"` (fresh test DB) | exit 0 |
| `ruff check --no-cache .` | All checks passed |
| `ruff format --check --no-cache .` | 118 files already formatted |
| `python manage.py makemigrations --check --dry-run` | No changes detected |
| `pytest` | **103 passed in 61.54 s** |
| `scripts/dev.sh openapi` (`spectacular --validate --fail-on-warn`) | exit 0; 123 API paths |
| `python manage.py migrate` (dev DB) | OK, then guards applied to 28 tables |
| psql check on the dev DB | 28 tables with RLS enabled and forced; 31 composite FKs; 5 append-only triggers; `rideflow_app` has rolsuper=f, rolbypassrls=f |
| `scripts\dev-up.ps1` | stack ready; `/health/ready` 200 (PostGIS 3.4.3, Redis ok) |

Tests per file:

| File | Tests |
|---|---|
| test_auth | 13 |
| test_backoffice | 10 |
| test_concurrency | 5 |
| test_drivers_geo | 12 |
| test_platform_basics | 6 |
| test_realtime | 3 |
| test_rides | 18 |
| test_subscriptions | 11 |
| test_tenant_isolation | 12 |
| test_trust | 13 |

Notable scenarios proven by these tests:

- **Isolation**
  - Every `/api/v1` route is called as a tenant-B user against tenant-A object ids. Routes with ids return 403/404, list routes leak no tenant-A ids, and tenant-A rows are unchanged. The test fails when a new route has no classification.
  - A forged tenant id in the payload is ignored, and a forged app header returns 401.
  - Raw SQL under RLS sees only the tenant's rows, and a cross-tenant insert is blocked by RLS.
  - A composite FK rejects a cross-tenant relation.
  - The ORM raises without a tenant context.
  - Config, currency and trust never cross tenants, and WebSocket hints never cross tenants.
- **Concurrency (real parallel transactions)**
  - Two riders select the same driver: exactly one wins, the other gets 409.
  - Duplicate selections produce one match.
  - The same Idempotency-Key sent 3 times in parallel creates one ride.
  - Two finance users approving the same claim create one subscription.
  - Parallel driver confirmations produce one assignment and one event.
- **Business rules**
  - No-show is refused without wait, geofence or contact evidence, and with inaccurate GPS.
  - Free cancellation versus late cancellation recorded for review.
  - No penalty for a driver declining.
  - Low stars alone never create sanctions.
  - Restrictions need activation, and appeals need a different reviewer.
  - Duplicate deposit reference or receipt is rejected, and maker-checker is enforced.
  - Trial is once per driver and capped.
  - Expired documents mid-shift block bidding.
  - A suspended tenant blocks new rides while active trips finish (OD-08).

Live smoke against the running server (real HTTP and ASGI, as the non-superuser RLS role):

- **Main flow:** OTP login for a demo rider, driver and owner, then location update, go online, estimate, ride creation, bid, select, confirm (fare locked at 120000), cancel and dashboard. All succeeded.
- **Isolation:**
  - A tenant-B admin reading a tenant-A ride got 404, and its list count was 0.
  - A forged app header got 401.
  - A platform token on tenant data got 403.

One issue found and fixed during the smoke test: a per-IP OTP limit of 5/hour was too strict for shared carrier NAT. It is now split into 5/hour per phone and 60/hour per IP, both configurable.

## 5. Key decisions

- **Owner-approved, recorded in 06_DECISION_LOG:**
  - D020 stack
  - D021 shared database with strict isolation
  - D022 global identity with tenant memberships
  - D023 tenant from the trusted app context, white-label ready
  - D024 Next.js admin; Django admin is internal only
  - D025 Flutter later
  - D026 cash fares and driver subscriptions, no commission
  - D027 driver confirmation required
- **Engineering, needs owner review (D028):**
  - one `Ride` aggregate
  - every business number is a tenant policy parameter labelled APPROVED/PROPOSED/PROVISIONAL (`GET /api/v1/admin/config`)
  - compensation and renewal discount disabled; dual approval off by default
  - dev OTP only

## 6. Known blockers and risks

- **Legal gate G0 (D013):** permits, insurance and vehicle eligibility in Hadramout are unverified. This blocks any real pilot.
- **Policy approvals pending:**
  - prices (D009)
  - wait time and geofence calibration (D010)
  - trust weights and tiers (D011)
  - deposit provider and settlement evidence (D014)
  - compensation (D015)
  - retention (OD-07)
  - break-glass (OD-09)
- **Before any shared or staging environment:** admin MFA and the production adapters (SMS, push, storage scanning).
- **WebSocket token in the query string:** proxies must not log query strings. Short-lived access tokens limit the exposure.

## 7. Local URLs (after `scripts\dev-up.ps1`)

| Purpose | URL |
|---|---|
| API | http://127.0.0.1:8010/api/v1/ |
| Swagger UI | http://127.0.0.1:8010/api/docs/ |
| ReDoc | http://127.0.0.1:8010/api/redoc/ |
| Schema | http://127.0.0.1:8010/api/schema/ |
| Health | http://127.0.0.1:8010/health/live, http://127.0.0.1:8010/health/ready |
| WebSocket | ws://127.0.0.1:8010/ws/v1/events/?token=ACCESS |
| Django admin (internal only) | http://127.0.0.1:8010/django-admin/ |

## 8. Phase 2 readiness

- **Ready:** the committed OpenAPI contract (`packages/contracts/openapi.yaml`), stable error, idempotency and versioning conventions, and the admin, report and dashboard APIs for the Next.js admin; rider and driver APIs plus the WebSocket and replay protocol for Flutter.
- **Recommended first Phase 2 tasks:**
  1. Admin MFA.
  2. Confirm CI is green on GitHub.
  3. Generate typed API clients from the contract.
  4. Next.js admin skeleton against `/api/v1/admin/*`.
  5. Owner approval of the PROPOSED/PROVISIONAL policy values.
