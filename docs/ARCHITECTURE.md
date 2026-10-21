# RideFlow — Architecture
Version 0.1 | 2026-10-21 | Stack is PROPOSED (D008); tenancy model is APPROVED (D017). ADRs in ADR/.

## 1. Context diagram
```
 Rider app (Flutter) ─┐                     ┌─ Tenant admin web
 Driver app (Flutter) ┼─ HTTPS REST /api/v1 ┤
                      └─ WSS (hints only) ──┘
                              │
                     services/api (Django + DRF, Channels)
        ┌──────────────┬──────┴───────┬───────────────┬──────────────┐
   Tenancy & Auth   Marketplace    Trips & Evidence  Trust & Disputes  Subscriptions & Ledger
        │              │              │                │                 │
        └──────── PostgreSQL + PostGIS (shared DB, tenant_id + RLS) ──────┘
                 Redis (cache, presence, rate limits, channel layer)
   Adapters: OTP/SMS, maps/geocoding, push, file storage (dev fakes in local)
   Platform admin (RideFlow staff): tenant provisioning only
```

## 2. Modules (services/api)
- tenancy: Tenant, TenantCity, TenantConfig, memberships, tenant context middleware.
- accounts: phone OTP, sessions, roles, admin MFA.
- drivers/vehicles: onboarding, documents, eligibility, review queue.
- marketplace: zones, fare guide, presence, requests, dispatch waves, bids, match.
- trips: state machine, TripEvent, LocationEvidence, cash declaration, amendments.
- trust: ratings, commitment metrics, Trust Score, tiers, violations, enforcement.
- disputes: disputes, appeals, evidence, reviewer audit.
- subscriptions: driver plans, deposit claims, reconciliation, credit ledger. (Future: saas_billing — separate module.)
- audit, feature flags, notifications.

## 3. Tenant isolation (ADR-0001)
1. Tenant resolved from the authenticated token claim (`tid`) issued at login; client-supplied tenant ids in body/query are ignored or must match.
2. Every tenant-scoped model inherits a base with non-null `tenant_id`; default manager requires tenant context and fails closed when absent.
3. Object-level authorization checks tenant + role + ownership on every endpoint; cross-tenant lookups return 404.
4. PostgreSQL row-level security policies on tenant tables using `current_setting('app.tenant_id')` set per transaction — defense in depth.
5. Composite FKs `(tenant_id, id)` so relations cannot cross tenants.
6. Caches, Redis keys, WebSocket groups, file storage paths, rate limits and background jobs are namespaced by tenant.
7. Platform admin access to tenant data only through audited break-glass.
8. Mandatory automated isolation test suite on every merge (TEST_PLAN §3).

## 4. API and real time
- REST `/api/v1`, OpenAPI as contract (packages/contracts); idempotency key + expected version on every mutation.
- WebSocket for hints only (new bid, status change); on reconnect client fetches REST snapshot and replays events by cursor.
- Push notifications best-effort, never correctness-critical.

## 5. Offline and sync
Cache current trip, contacts, route text, signed snapshot, limited command queue with UUIDs. No offline bid acceptance or authoritative arrival. UI shows "pending sync" and stale-location markers.

## 6. Money and configuration (ADR-0003)
Amounts stored as integer minor units with ISO-4217 currency per tenant; no cross-currency arithmetic; policy parameters versioned in TenantConfig with effective dates; trips snapshot the config version used.

## 7. Observability and security
Structured logs with tenant_id and request id, PII redaction; metrics per tenant; SLOs and incident playbook (S09). TLS, short-lived signed tokens with revocation, throttling, upload scanning/size caps, encrypted sensitive PII, backups with restore drill, secret scanning in CI.

## 8. Repository layout
Target: apps/rider, apps/driver, apps/admin, services/api, packages/contracts, infra/docker, docs, tests/e2e.
Created in Phase 1: services/api (Django modular apps), packages/contracts (OpenAPI), infra/docker, scripts, .github/workflows. apps/admin will be Next.js (D024); apps/rider and apps/driver will be Flutter (D025).

## 9. Phase 1 implementation notes
- Tenant resolution: `X-RideFlow-App` (registered TenantApplication) for OTP; afterwards JWT claim `tid` (D023). Global users with tenant memberships (D022).
- RLS: `app.tenant_id` / `app.rls_bypass` session settings mirror the request context. API requests start "locked" (no tenant rows) until authentication binds a tenant. System mode (bypass) is used only by migrations, management commands, the timeout worker and Django admin.
- Rides: one `Ride` aggregate with an explicit state machine (`apps/rides/state_machine.py`), row locks, `expected_version`, append-only `RideEvent` (replay cursor `seq`), partial unique indexes (one active ride per driver and per rider, one live bid per driver per ride).
- Timers (bid expiry, confirmation timeout, unmatched expiry) are applied lazily on access and by the `worker` service (`process_timeouts --loop 5`).
