# ARCHITECTURE, STATE MACHINE AND API CONTRACT

## Stack recommendation
Flutter rider and driver apps; Django + DRF backend; Django Channels/WebSocket or equivalent adapter; PostgreSQL/PostGIS; Redis; separate admin web (Django admin initially or dedicated frontend if justified); Docker Compose dev; CI tests. Map/SMS/push adapters abstract providers and permit dev fakes.

## Repo layout
apps/rider; apps/driver; apps/admin; services/api; packages/contracts; infra/docker; docs; tests/e2e.

## Multi-tenancy (D017, ADR-0001)
Shared PostgreSQL database; every operational record carries tenant_id; tenant derived from the authenticated token, never trusted from client payload; all queries scoped through a tenant-aware data layer plus PostgreSQL row-level security as defense in depth; composite foreign keys (tenant_id, id) prevent cross-tenant relations. See ../ARCHITECTURE.md and ../DATA_MODEL.md.

## Core entities
Tenant, TenantCity, TenantConfig, TenantMembership, User, PhoneVerification, DriverProfile, DriverDocument, Vehicle, VehicleDocument, DriverEligibility, ServiceZone, FareGuide, DriverPresence, RideRequest, Bid, Match, Trip, TripEvent, LocationEvidence, PaymentCashDeclaration, Rating, CommitmentMetric, Violation, Dispute, Appeal, SubscriptionPlan, Subscription, DepositClaim, Reconciliation, CreditLedger, AuditEvent, FeatureFlag.

## Critical constraints
One active match per request; at most one active trip per driver; no selection of expired/revoked bid; price immutable after match except explicit signed amendment; DB transaction with row locking/unique constraints; every mutation has idempotency key and expected state/version. Server timestamps authoritative; app device clock untrusted. Audit immutable sensitive changes.

## Candidate REST endpoints (versioned /api/v1)
POST /auth/request-otp, /auth/verify-otp; GET /me; POST /driver/onboarding; GET /driver/status; POST /driver/presence; POST /rides; GET /rides/{id}; POST /rides/{id}/cancel; POST /rides/{id}/bids; POST /rides/{id}/select; POST /rides/{id}/driver-confirm; POST /trips/{id}/arrive, /start, /complete, /amend; POST /trips/{id}/cash-confirm; POST /trips/{id}/rating; POST /trips/{id}/disputes; POST /subscriptions/deposit-claims; GET /subscriptions/current; admin review endpoints. Final schemas to be documented as OpenAPI and reviewed before UI integration.

## Real time
WebSocket only for hints (new bids/status), never sole truth. On reconnect, fetch authoritative REST snapshot and replay events by cursor. Push notifications can be delayed; clients must not rely on delivery for correctness.

## Offline
Cache only current trip, relevant contact and route text, signed state snapshot and limited event queue. No offline acceptance of expired bids or authoritative arrival determination; show 'pending sync'. Queue commands with UUID and replay-safe API; do not promise offline dispatch.

## Security
Role and object checks for every endpoint, separate admin MFA, signed short-lived access tokens and revocation, request throttling, file upload scanning/size caps, sensitive PII encryption/retention, minimal telemetry, back-up/restore and secrets rotation. GPS accuracy/spoof detection advisory, not perfect proof.

## Acceptance scenarios
Two riders selecting same driver simultaneously; two driver confirmations for one request; bid expires before selection; duplicate deposit photo/reference; user resends start command offline; network disconnect after server commits; location spoof; 5000ms/30000ms delays; out-of-order location updates; forged trip ID; driver license expires; two administrators approve same claim; rating retaliation; geofence inaccurate in dense streets.
