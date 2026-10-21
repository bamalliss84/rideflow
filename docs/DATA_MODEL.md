# RideFlow — Data Model
Version 0.1 | 2026-10-21 | Logical model; final schema decided in implementation tasks with migrations.

## Conventions
- PK `id` UUID. All tenant-scoped tables: `tenant_id` NOT NULL, FK Tenant, composite unique `(tenant_id, id)`; child FKs reference `(tenant_id, parent_id)`.
- RLS enabled on tenant-scoped tables. Timestamps server-side UTC; tenant time zone for display.
- Money: `amount_minor BIGINT` + `currency CHAR(3)` (must equal tenant currency in MVP).
- Sensitive mutations write AuditEvent; ledgers are append-only.

## Platform-level (not tenant-scoped)
| Entity | Key fields |
|---|---|
| Tenant | name, slug, status(active/suspended), default_currency, time_zone, locale |
| PlatformAdmin | user ref, MFA |
| (Future) SaasPlan, SaasSubscription, SaasInvoice | tenant → RideFlow billing; separate from driver subscriptions |

## Tenant-scoped
| Area | Entities |
|---|---|
| Tenancy | TenantCity(name, geom), TenantConfig(version, effective_from, params JSON validated), TenantMembership(user, role) |
| Identity | User(phone unique per tenant), PhoneVerification, Session |
| Drivers | DriverProfile, DriverDocument(expiry), Vehicle(plate unique per tenant), VehicleDocument, DriverEligibility |
| Marketplace | ServiceZone(city, polygon), FareGuide, DriverPresence(point, accuracy), RideRequest, DispatchWave, Bid(amount, eta, expires_at, status), Match |
| Trips | Trip(state, version, price_locked, config_version), TripEvent, LocationEvidence(point, accuracy, server_ts, device_ts), TripAmendment, PaymentCashDeclaration |
| Trust | Rating, CommitmentMetric, TrustScore(snapshot, method_version), TierAssignment, Violation, EnforcementAction |
| Disputes | Dispute, DisputeEvidence, Appeal |
| Driver subscriptions | SubscriptionPlan, Subscription, DepositAccount, DepositClaim(reference, receipt_hash), Reconciliation, CreditLedgerEntry |
| Ops | AuditEvent, FeatureFlag, IdempotencyKey |

## Key constraints
- Partial unique: one active Match per RideRequest; one active Trip per driver.
- Unique (tenant_id, phone) on User; (tenant_id, plate) on Vehicle; (tenant_id, deposit reference) and (tenant_id, receipt_hash) on DepositClaim.
- Bid selectable only if status=open and expires_at > now (checked in transaction with row lock).
- Trip `version` for optimistic concurrency; state transitions validated server-side.

## Indexes
GiST on DriverPresence.point, ServiceZone.polygon, TenantCity.geom; B-tree leading with tenant_id on all hot lookups (e.g. (tenant_id, state, created_at) on Trip; (tenant_id, request_id, status) on Bid).

## Phase 1 implementation mapping (D028)
- `User` is global (D022); `TenantMembership(tenant, user, role, status)` grants access. PhoneVerification → `PhoneOTP` (HMAC only).
- RideRequest + Match + Trip → `rides.Ride`; `Bid`, `DispatchCandidate`, `RideEvent`, `LocationEvidence`, `RideAmendment`; cash declaration fields live on `Ride`.
- CommitmentMetric/TrustScore/TierAssignment → `trust.TrustSnapshot` (components JSON, `method_version`); Violation, EnforcementAction, Dispute (+DisputeNote), Appeal, Rating.
- Reconciliation → maker-checker fields on `DepositClaim`; CreditLedgerEntry → `SubscriptionLedgerEntry`; DriverSubscription periods.
- Composite FKs and RLS are applied automatically after every migrate for all tenant-scoped models (`apps/core/db.py`).

## Retention (to be finalized — OD-07)
Precise location and documents: limited retention, role-restricted; audit and ledgers: long retention.
