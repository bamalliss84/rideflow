# RideFlow

Multi-tenant ride-hailing SaaS backend. A **tenant** is an independent transportation operator, which may run in several cities. Mukalla, Yemen is the first pilot city; it is demo data, not a platform restriction (D017).

**Phase 1 status:** the backend API is implemented and tested locally. The Next.js admin dashboard and the Flutter rider and driver apps come in later phases. See [docs/reports/PHASE_01_BACKEND_REPORT.md](docs/reports/PHASE_01_BACKEND_REPORT.md) for scope, test evidence and open items.

## Stack

- Django 5.2 LTS, Django REST Framework, drf-spectacular (OpenAPI 3).
- PostgreSQL 16 with PostGIS 3.4, using a shared database and PostgreSQL row-level security.
- Redis 7: cache, throttling and the Channels layer.
- Django Channels and Daphne for WebSocket hints.
- Docker Compose for local development. The source code stays on the Windows host as a bind mount.

## Repository layout

```
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
2. Starts `db`, `redis`, `api` and `worker`.
3. Applies migrations and waits for `/health/ready`.
4. Loads the demo data.

| URL | Purpose |
|---|---|
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

## Tests and CI

`scripts\test.ps1` runs the same checks as CI: `ruff` lint and format, migration consistency, and the full pytest suite against PostGIS. The suite covers tenant isolation (including a generated check of every route), permission negatives, parallel-transaction concurrency scenarios and WebSocket tests. GitHub Actions (`.github/workflows/ci.yml`) also runs a gitleaks secret scan, checks that the OpenAPI contract is up to date and runs a Docker smoke test.
