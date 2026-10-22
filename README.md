# RideFlow

Multi-tenant ride-hailing SaaS backend. A **tenant** is an independent transportation operator, which may run in several cities. Mukalla, Yemen is the first pilot city; it is demo data, not a platform restriction (D017).

**Status:**

- **Phase 1:** backend API ([report](docs/reports/PHASE_01_BACKEND_REPORT.md)).
- **Phase 2:** administration portal for platform staff and transport operators, Arabic-first ([report](docs/reports/PHASE_02_ADMIN_REPORT.md)).
- **Later phases:** Flutter rider and driver apps.

## Stack

- Django 5.2 LTS, Django REST Framework, drf-spectacular (OpenAPI 3).
- PostgreSQL 16 with PostGIS 3.4, using a shared database and PostgreSQL row-level security.
- Redis 7: cache, throttling and the Channels layer.
- Django Channels and Daphne for WebSocket hints.
- Docker Compose for local development. The source code stays on the Windows host as a bind mount.
- Admin portal (`apps/admin`): Next.js 16 App Router, React 19, TypeScript (strict), Tailwind CSS 4, TanStack Query, lucide icons, and IBM Plex Sans Arabic (self-hosted).

## Repository layout

```
apps/admin/              Next.js admin portal (platform + operator), BFF auth, design system
services/api/            Django project (rideflow/) and modular apps (apps/*)
  apps/core              tenant context, RLS guards, idempotency, audit, health, permissions
  apps/tenancy           tenants, white-label app contexts, memberships, versioned tenant policy
  apps/accounts          global users, OTP login (dev adapter), JWT with tenant claim
  apps/drivers           onboarding, documents, vehicles, review queue, eligibility, availability
  apps/geo               cities, service areas, driver presence, nearby search, fare estimate
  apps/rides             ride state machine, dispatch waves, bids, match, trip, amendments
  apps/subscriptions     plans, deposit receipts (maker-checker), entitlement, immutable ledger
  apps/trust             ratings, trust scores, incidents, enforcement ladder, disputes, appeals
  apps/notifications     persisted notifications, WebSocket hints, reconnect replay
  apps/backoffice        platform provisioning, tenant admin, dashboard metrics, reports
  tests/                 pytest suite (isolation, concurrency, realtime, business rules)
packages/contracts/      committed OpenAPI contract (openapi.yaml) for future clients
infra/docker/            PostGIS init (non-superuser app role so RLS applies)
scripts/                 dev-up.ps1, test.ps1, export-openapi.ps1, dev.sh
docs/                    PRD, architecture, ADRs, business rules, project management, reports
```

## Quick start (Windows, PowerShell)

Requirements: Docker Desktop (Compose v2) and Git.

```powershell
powershell -ExecutionPolicy Bypass -File scripts\dev-up.ps1 -Build -Seed
```

This command:

1. Creates `.env` from `.env.example`. The values are for development only, and `.env` is never committed.
2. Starts `db`, `redis`, `api`, `worker` and `admin`.
3. Applies migrations and waits for `/health/ready`.
4. Loads the demo data.

| URL | Purpose |
|---|---|
| **http://localhost:3000** | **Admin portal: operator sign-in at `/login`, RideFlow staff at `/platform/login`** |
| http://127.0.0.1:8010/api/v1/ | REST API v1 |
| http://127.0.0.1:8010/api/docs/ | Swagger UI |
| http://127.0.0.1:8010/api/redoc/ | ReDoc |
| http://127.0.0.1:8010/api/schema/ | OpenAPI schema |
| http://127.0.0.1:8010/health/live, /health/ready | Liveness and readiness |
| ws://127.0.0.1:8010/ws/v1/events/?token=ACCESS | WebSocket hints |
| http://127.0.0.1:8010/django-admin/ | Internal technical administration only |

The host port comes from `API_PORT` in `.env`. The default is 8010 because 8000 is often taken.

Other commands:

```powershell
powershell -ExecutionPolicy Bypass -File scripts\test.ps1            # lint, format, migrations, full test suite
powershell -ExecutionPolicy Bypass -File scripts\export-openapi.ps1  # refresh packages/contracts/openapi.yaml
docker compose down                                                  # stop (keeps data volumes)
```

`scripts/dev.sh up|seed|test|openapi|down` does the same from Git Bash, Linux or CI.

## Admin portal sign-in (local demo)

**Local Docker development (default since D033):** administrator logins skip the TOTP step.

- **Operator:** workspace, phone, dev OTP `000000`, then the dashboard.
- **Platform:** phone and password, then the dashboard.

This is controlled by `DEV_ADMIN_MFA_BYPASS=1` together with `RIDEFLOW_ENV=local`, which `docker-compose.yml` sets for the dev stack only. The API refuses the flag unless `DJANGO_DEBUG=1` and `RIDEFLOW_ENV=local`. To test real MFA locally, set `DEV_ADMIN_MFA_BYPASS=0` in `.env` and run `docker compose up -d --build`.

With real MFA enabled:

- **Operator portal:** open http://localhost:3000/login and follow these steps:
  1. Enter workspace `demo-mukalla-admin` and phone `+967700000001` (owner).
  2. Enter the dev OTP `000000`.
  3. On first sign-in, set up an authenticator app: scan the QR code or type the key.
  4. Enter the 6-digit code from the app.

  Finance (`+967700000002`) and reviewer (`+967700000003`) see role-restricted menus.
- **Platform portal:** open http://localhost:3000/platform/login and sign in with `DEMO_PLATFORM_ADMIN_PHONE` and `DEMO_PLATFORM_ADMIN_PASSWORD`, followed by the same authenticator steps.
- **Development only — demo authenticator lost or enrolled by someone else.** Run the reset below. It refuses unless `DJANGO_DEBUG=1`, writes an audit event, and never reveals a secret. The next sign-in shows the setup QR code again.

  ```bash
  docker compose exec api python manage.py dev_reset_mfa +967700000001 --i-understand
  ```
- **Lost authenticator:**
  - an operator owner or admin can reset a staff member's authenticator under **Members**;
  - RideFlow staff can reset an operator owner's or admin's authenticator from the operator page.

## Demo data (`seed_demo`, idempotent, all fake)

| Tenant | Apps (`X-RideFlow-App`) | Users |
|---|---|---|
| `mukalla-pilot` (YER, Asia/Aden) | `demo-mukalla-rider`, `demo-mukalla-driver`, `demo-mukalla-admin` | owner `+967700000001`, finance `+967700000002`, reviewer `+967700000003`, riders `+96771100000[1-3]`, drivers `+96772200000[1-5]` |
| `demo-b` (SAR, Asia/Riyadh) | `demo-b-rider`, `demo-b-driver`, `demo-b-admin` | owner `+967700000101`, rider `+967711000101`, driver `+967722000101` |

- The development OTP code is `OTP_DEV_CODE` from `.env` (default `000000`). The dev OTP adapter only logs it and sends no SMS.
- The platform admin logs in through `POST /api/v1/auth/platform/login` with `DEMO_PLATFORM_ADMIN_PHONE` and `DEMO_PLATFORM_ADMIN_PASSWORD`.
- Demo drivers count as present only for `presence.stale_seconds` after their last `POST /api/v1/driver/location`, so send a location update before you request a ride.

## API conventions

- **Tenant context.** Clients send `X-RideFlow-App: <client_id>` on the OTP endpoints. The client id identifies a registered tenant application, which allows white-label apps per operator. After login, the tenant comes only from the JWT claim `tid`. Tenant ids in request bodies are ignored. A request whose app header belongs to another tenant is rejected with 401.
- **Identity.** A phone number is one global user. Access to an operator comes from tenant memberships with roles: `rider`, `driver`, `owner`, `admin`, `reviewer`, `finance`, `support`.
- **Idempotency.** Critical mutations require an `Idempotency-Key` header. A retry with the same key and payload replays the stored response (`Idempotent-Replay: true`). The same key with a different payload returns 422.
- **Optimistic concurrency.** Ride lifecycle actions require `expected_version`. A stale version returns 409 with `current_version`.
- **Errors.** Errors return `{"code": "...", "detail": ...}`, or `{"code": "invalid", "errors": {...}}` for validation errors.
- **Money.** Amounts are integer minor units, `*_minor`, in the tenant currency. The API never uses floats for money and never does cross-currency arithmetic.
- **Real time.** WebSocket messages are hints only: `{"type":"hint","cursor":n,"kind":"ride.bid_created","payload":{ids}}`. To recover after a reconnect, send `{"type":"resume","cursor":last}` or call `GET /api/v1/notifications?after=<cursor>`, then refetch the REST snapshot.

## Security model (summary)

- **Defense in depth for tenant isolation.**
  - A fail-closed ORM manager raises when a query runs without a tenant context.
  - PostgreSQL `FORCE ROW LEVEL SECURITY` applies to every tenant table, and the app connects as a role with `NOSUPERUSER NOBYPASSRLS`.
  - Composite foreign keys `(tenant_id, id)` prevent relations across tenants.
  - Redis keys, WebSocket groups and file paths are namespaced by tenant.
  - Cross-tenant lookups return 404.
- **Append-only records.** Audit events, ledgers, ride events, location evidence and config versions are append-only, and database triggers reject UPDATE and DELETE.
- **No automatic penalties.** The system never fines anyone and never sanctions from star ratings or a single GPS fix. Incidents require human verification, restrictions require human activation, and appeals are decided by a different reviewer.

## Admin portal security (ADR-0005)

- **BFF sessions.** The browser talks only to the Next.js server, never directly to the API.
  - JWTs live in HttpOnly, SameSite=Strict cookies.
  - Mutations require a same-origin request and a CSRF double-submit token.
  - Expired access tokens are renewed by one single-flight refresh.
- **Mandatory administrator MFA.** Administrator accounts must use TOTP. Staff permissions exist only in MFA-verified sessions.
- **Separate portals.** Platform and operator sessions are separate. The UI hides actions the role cannot perform, but the API remains the only security boundary.

## Tests and CI

`scripts\test.ps1` runs the same checks as CI: `ruff` lint and format, migration consistency, and the full pytest suite against PostGIS. The suite covers tenant isolation (including a generated check of every route), permission negatives, parallel-transaction concurrency scenarios and WebSocket tests. GitHub Actions (`.github/workflows/ci.yml`) also runs a gitleaks secret scan, checks that the OpenAPI contract is up to date and runs a Docker smoke test.
