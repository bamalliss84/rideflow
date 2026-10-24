# Phase 3: release readiness

Status: **not production-ready yet. Ready as a tested baseline for Phase 4 (Flutter driver app) development against the local and staging API.**

Nothing below is represented as done unless the "Status" column says so.

## Release blockers (must be resolved before a real pilot)

| ID | Item | Type | Status |
|---|---|---|---|
| R-01 | Production ASGI server and deployment (e.g. uvicorn/daphne workers behind a TLS reverse proxy, separate worker process, static/media plan). Only a development entrypoint (`runserver`) exists; measured throughput is dev-server bound. | Engineering | Open |
| R-02 | SMS OTP provider. Only the development adapter exists, and it refuses to run with DEBUG off. | External / paid provider | Open (D028) |
| R-03 | Malware scanning of uploaded documents and receipts (content-type sniffing and size limits exist, no AV scan). | External / provider | Open |
| R-04 | Push notifications (FCM/APNs) for driver and rider apps. Hints exist over WebSocket and replay only. | External / provider | Open |
| R-05 | Real map tiles and geocoding. Admin maps are schematic SVG (D032). | External / provider | Open |
| R-06 | Legal: permits, insurance, business registration, operating boundaries (D013), deposit/wallet provider and settlement evidence (D014). | Legal / owner | Open |
| R-07 | Owner approval of PROPOSED/PROVISIONAL policy values (D009, D010, D011, D015). Values are shown as unapproved in the portal and were not changed. | Owner decision | Open |
| R-08 | Production configuration (see below), in particular trusted-proxy hops. With no trusted proxy, every admin portal user shares the BFF's IP for per-IP throttles, so an attacker could exhaust the shared admin OTP IP budget (availability risk; per-phone limits still apply). | Ops | Open; documented in `.env.example` |
| R-09 | Backups, restore drill, monitoring and alerting, log retention. | Ops | Open |
| R-10 | Operator-surveyed service areas. Demo geometry only. | Owner / ops | Open |

## Production configuration checklist

Settings enforced by code since Phase 3 (the API refuses to start otherwise when `DJANGO_DEBUG=0`):

| Setting | Requirement | Enforced |
|---|---|---|
| `DJANGO_SECRET_KEY` | random, ≥ 50 characters, not a dev placeholder | Yes (P3-02) |
| `MFA_ENCRYPTION_KEY` | explicit Fernet key | Yes (P3-03) |
| `OTP_PROVIDER` | not `dev` | Yes (Phase 1) |
| `DEV_ADMIN_MFA_BYPASS` | off, and only possible with DEBUG + `RIDEFLOW_ENV=local` | Yes (D033) |
| HSTS | `SECURE_HSTS_SECONDS` default 1 year | Default (P3-06) |
| Secure cookies | API session/CSRF cookies; BFF `COOKIE_SECURE` defaults to true | Default |
| API docs | hidden unless `API_DOCS_ENABLED=1` | Default (P3-06) |

To set per deployment:
- `DJANGO_ALLOWED_HOSTS`, `DJANGO_CSRF_TRUSTED_ORIGINS` and database credentials (non-default).
- `API_TRUSTED_PROXY_COUNT` / `ADMIN_TRUSTED_PROXY_COUNT` = number of TLS proxies that append `X-Forwarded-For`.
- `SECURE_SSL_REDIRECT=1` if TLS is not redirected at the proxy.

## Verified in Phase 3

Evidence is in [PHASE_03_QA_REPORT.md](PHASE_03_QA_REPORT.md).

- **Tenant isolation:** reads, writes, verbs, objects and headers; RLS and fail-closed ORM.
- **Authentication:** platform/operator separation; RBAC; maker-checker and own-case rules.
- **MFA:** enforced; local-only dev bypass with revocation; new one-time recovery codes.
- **Sessions:** rotation, CSRF, HttpOnly/SameSite cookies.
- **Abuse resistance:** throttles that cannot be spoofed; idempotency and concurrency.
- **Core workflows** (backend tests + E2E): driver onboarding review, deposit review → subscription → ledger, ride lifecycle with cash fare, disputes → violations, appeals (backend), policy versioning, notifications, reports/CSV.
- **Admin portal:** RTL/LTR and responsive layout at 375/768/1280/1440 px.

## Known limitations (non-blocking)

- No unread-count endpoint for the notification bell (Phase 2 note).
- No free-text member search (API has role/status filters only).
- E2E runs locally only (full stack plus Chrome). It is not in CI.
- Browser coverage: Chrome only; WebKit/Firefox and real devices not tested.
- OTP throttles (5 requests per phone per hour) can lock out a legitimately retrying user for up to an hour. This is by design and should be reviewed with real SMS costs.
