# RideFlow — Test Plan
Version 0.1 | 2026-10-21 | No tests exist yet (no code). Definition of Done: 04_EXECUTION_AND_QA.md.

## 1. Levels
- Unit: state machine transitions, pricing/minor-unit math, trust scoring, enforcement ladder, config versioning.
- Integration (API + PostgreSQL/PostGIS + Redis): auth, object-level authorization, bidding/match transactions, deposits, ledgers.
- Contract: OpenAPI compatibility checks for Flutter clients.
- E2E: rider + driver complete cash ride on emulators/devices; admin approval flows.
- Field: real low-network tests in Mukalla neighborhoods before pilot.

## 2. Concurrency & resilience (required before merge of related tasks)
Two riders/selections for same driver; two driver confirmations; bid expires during selection; duplicate start command after reconnect; disconnect after server commit; 5 s / 30 s latency; out-of-order location updates; clock skew; multi-device session.

## 3. Tenant isolation suite (mandatory on every merge, D017)
For every endpoint and model: user of tenant A cannot read/list/update/delete tenant B objects (expect 404); forged tenant id in payload/header ignored; relations across tenants rejected by DB (composite FK) and RLS; Redis keys, WS groups, file URLs and background jobs scoped; Trust Score/ratings never aggregate across tenants; config/currency of A never applied to B; platform admin access produces audit events.
Generated test: enumerate registered routes and assert isolation coverage — CI fails if a route lacks an isolation test.

## 4. Business rule tests
Cancellation matrix windows; no-show only with wait + geofence + contact evidence; no penalty for not bidding; no sanction from stars alone; compensation caps; duplicate deposit rejection; maker-checker; price immutability.

## 5. Security
Secret scanning, dependency audit, OTP abuse limits, upload validation, token revocation, admin MFA.

## 6. Evidence rules
Report exact commands and exit codes; never claim passing tests not run; attach screenshots/video for UI.
