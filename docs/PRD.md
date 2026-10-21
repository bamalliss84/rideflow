# RideFlow — Product Requirements (PRD)
Version 0.1 | 2026-10-21 | Status: BASELINE (T00-B), not implemented
Sources of truth: project-management/06_DECISION_LOG.md (D001–D019), 01_MASTER_ROADMAP.md, 02_BUSINESS_POLICY.md.

## 1. Product
RideFlow is a multi-tenant ride-hailing SaaS. A **tenant** is an independent transportation operator that may run service in one or more cities. RideFlow (the platform) supplies software; each tenant operates its own riders, drivers, pricing and policies. First pilot: one tenant in Mukalla, Yemen (D001, D017).

## 2. Actors
| Actor | Scope |
|---|---|
| Rider | Belongs to one tenant account; requests rides, selects bids, pays cash, rates |
| Driver | Belongs to one tenant account; bids, completes trips, receives cash, pays driver subscription |
| Tenant admin / reviewer | Operator staff; approves drivers, deposits, disputes; configures tenant policy |
| Platform admin | RideFlow staff; provisions tenants; no routine access to tenant operational data (audited break-glass only) |

## 3. Scope: MVP vs Future SaaS
### MVP (pilot, P0) — all records tenant-scoped
- Tenant foundation: Tenant, TenantCity, TenantConfig, memberships; tenants provisioned by platform admin (seed/admin form).
- Tenant-specific currency, fare guidance, cancellation/no-show parameters, driver subscription plans, rating/trust parameters.
- Identity & eligibility (S01), geolocation/estimate/competitive bidding (S02), trip lifecycle & cash (S03), trust/conduct/disputes incl. Trust Score, no-show, compensation credits (S04), driver subscriptions with manual deposit verification (S05), rider & driver Flutter apps (S06–S07), tenant admin web (S08), security/reliability (S09).
- Weak-network-first operation; Arabic RTL.
- Operated in production for **one tenant, one city** (Mukalla); data model already supports many tenants and cities.

### Future SaaS capabilities (P1/P2, not in MVP)
- Self-service tenant signup and onboarding wizard.
- SaaS operator subscriptions/billing (separate product and ledger from driver subscriptions).
- White-label branding, per-tenant app builds/domains.
- Multi-city rollout tooling, cross-city reporting per tenant.
- Tenant data export, offboarding and deletion automation.
- E-wallets/electronic payments, public API/webhooks, platform-level benchmarking.
- Growth features: referrals, vouchers, scheduled/airport/corporate rides (R10).

## 4. Key user stories (MVP)
- Rider: enter pickup/drop-off + landmark, see indicative range (not binding), receive competing bids (price, ETA, stars, completed rides, commitment, verification), select one, track, pay cash, rate driver, raise dispute.
- Driver: complete onboarding & documents, pay subscription by deposit and upload receipt, go available, receive staged requests, bid or ignore without penalty, confirm, arrive/wait/start/end, confirm cash, rate rider, appeal.
- Tenant admin: approve drivers/vehicles, reconcile deposits (maker-checker), review disputes/no-shows with evidence, configure zones, fares, policy parameters, view KPIs.
- Platform admin: create tenant, set its currency/time zone/cities, create first tenant admin.

## 5. Screens (MVP)
Rider: onboarding/OTP, home/location+landmark, estimate, bid list, match status, active trip, cash/receipt, rating, history, disputes.
Driver: onboarding & documents, verification status, subscription & deposit upload, availability, request/bid, confirmation, active trip (arrive/wait/start/end), cash confirm, rating, earnings & commitment metrics.
Tenant admin web: driver/vehicle queue, deposit queue, disputes/appeals, trip explorer, configuration, dashboard, audit log.
Platform admin: tenant list/create/suspend.

## 6. Edge cases (must be specified and tested)
Concurrent selections/confirmations; bid expiry at selection; reconnect after server commit; duplicate commands; out-of-order location; GPS inaccuracy at geofence; duplicate deposit receipts; expired driver documents mid-shift; tenant suspended mid-trip; user attempting to access another tenant's object; currency/rounding differences between tenants.

## 7. Non-functional
Strict tenant isolation; server-authoritative state; idempotent mutations; low bandwidth (small payloads, REST snapshot + hint WebSocket); privacy (coarse location exposure, retention); audit of sensitive changes; Arabic RTL first.

## 8. Explicit MVP exclusions
No cash fines; no stored cards; no auto punishment from one GPS point or stars; no "buy higher trust"; no offline bidding guarantee; no cross-tenant rider/driver marketplace.
