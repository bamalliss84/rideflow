# MASTER ROADMAP — full feasibility-study feature register
Status: Proposed backlog. Priority P0=pilot must-have, P1=post-pilot, P2=scale. Completion requires proof, not checkbox only.

## Delivery gates
G0 legal/market validation: verify local commercial and transport permits, vehicle eligibility, driver documentation, insurance obligations; interview 20–30 drivers and 30 riders, validate price willingness. Gate may run in parallel with local technical prototype, but must pass before real public pilot.
G1 runnable skeleton; G2 authenticated complete cash ride; G3 trusted/low-bandwidth pilot; G4 controlled staging; G5 commercial launch.

## S00 Foundations [P0]
R00-01 monorepo apps/rider, apps/driver, apps/admin, services/api, infra, docs.
R00-02 pinned versions, local Docker PostGIS/Redis, CI lint/tests, .env.example, README, branch protection guidance.
R00-03 PRD, ADRs, threat model, API contract, DB schema, decision log, seed/demo fixtures.
R00-04 Arabic RTL UX system, low-bandwidth principles, telemetry with PII redaction.
R00-05 Tenant foundation (D017): Tenant, TenantCity, tenant-scoped users/config/currency, isolation enforced in auth, authorization, API, queries and relations; tenants provisioned by platform admin. All S01–S09 records are tenant-scoped.

## S01 Identity, eligibility and profiles [P0]
R01-01 rider phone registration, OTP adapter (dev fake only), session revocation and abuse throttles.
R01-02 driver onboarding: phone, identity, photo, license, car registration, plate, photos, document expiry, review queue.
R01-03 vehicle/driver status and permit eligibility check, verification badge, admin approval/rejection reason, audit log.
R01-04 role-based access, admin MFA, safe document storage and retention.

## S02 Geolocation, quote and marketplace [P0]
R02-01 pickup/drop-off coordinates plus human-readable landmarks, area selection and editable meeting point.
R02-02 indicative price range using configured zones/distance and historical completed rides only when sufficient sample; clear 'estimate, not guaranteed'.
R02-03 driver availability, configurable geo-radius, staged waves of 5–10 nearby eligible drivers; no broadcast to entire city.
R02-04 driver bid amount, ETA estimate, expiration, rider live bid comparison (price, ETA, stars, completed rides, commitment, verification).
R02-05 rider selection and driver confirmation policy as configured; atomic match and single-winner constraint; bid expiry, race/retry and idempotency.
R02-06 no penalty for rider declining all bids or driver declining to bid.

## S03 Trip lifecycle and cash [P0]
R03-01 finite states REQUESTED/BIDDING/MATCH_PENDING/ASSIGNED/EN_ROUTE/ARRIVED/IN_PROGRESS/COMPLETED/CANCELLED/NO_SHOW/DISPUTED with allowed transitions and actor checks.
R03-02 arrival geofence plus accuracy/timestamps, waiting timer, call via normal phone, notification retries.
R03-03 start/end trip, price lock, destination/price amendment requiring both parties' acceptance, cash due and cash-received acknowledgment (no platform custody).
R03-04 trip receipts/history, cancellations and reason codes, rider/driver support and emergency/share-trip link only with privacy/security review.

## S04 Trust, conduct and disputes [P0]
R04-01 bilateral 1–5 stars plus reason tags; weighted reputation with Bayesian prior/minimum sample; show sample count and avoid new-user penalty.
R04-02 separate objective commitment metrics from subjective stars; no automated punishment based only on low stars.
R04-03 verified rider no-show: eligible arrival evidence, wait timer, contact attempt event, rider response, GPS uncertainty, human appeal; avoid GPS-only verdict.
R04-04 symmetric driver late cancellation/no-show and rider protection; graduated warnings, temporary limits, recovery/expiry windows.
R04-05 dispute case, evidence provenance, reviewer audit trail, manual override with reason and appeal window.
R04-06 driver compensation in capped subscription credits/days only for approved events; prevent abuse; credit ledger and liability ceiling.
R04-07 bronze/silver/gold/diamond and subscription renewal discount for verified good conduct; objective published thresholds; fairness and anti-retaliation checks.
R04-08 fair driver exposure; paid tier cannot purchase trust score or conceal violations.

## S05 Subscriptions and accounting [P0]
R05-01 configurable founder trial (proposed 60 days/first 100 drivers; requires owner approval), monthly tier proposed 5,000 YER; pricing is hypothesis.
R05-02 deposit instructions, unique payment reference, upload receipt, duplicate hash/reference detection, admin maker-checker for approval, status and expiry.
R05-03 immutable ledger for paid subscriptions, discounts, no-show credits, reversals; reconciliation exports, reminders, expiry/grace logic.
R05-04 optional weekly tier and professional tier [P1], electronic wallet integration [P2] after provider validation.

## S06 Rider Flutter [P0]
R06-01 Arabic-first onboarding, location/landmark selection, estimate, bid list, selection/confirmation, ride card, map, call, cash, rating, history, disputes.
R06-02 offline cached assigned trip and queued safe commands; clearly mark stale location; accessibility, battery/data optimization.

## S07 Driver Flutter [P0]
R07-01 verification progress, vehicle, subscription, available toggle, ride requests, bid entry, confirmation, navigate, arrived/wait/start/end, cash, rating.
R07-02 earnings stats (cash declared, not platform revenue), commitment metrics, subscription renewal and receipts, low-network retry.

## S08 Admin web and reporting [P0]
R08-01 approve drivers/vehicles, subscription deposits, fraud flags, dispute queue, trip explorer and immutable audit logs.
R08-02 configure areas, fare guidance, geofence/wait policy, thresholds, rollout flags; permission gates.
R08-03 dashboard: eligible/online drivers, requests, bid coverage, match, completion, cancellations, no-show, median ETA, repeat riders, paid retention.

## S09 Security/reliability/release [P0]
R09-01 API object-level authorization, rate limits, OTP abuse, secure tokens, encrypted transport, secrets, backup restore drill.
R09-02 idempotent commands, reconnect/replay, out-of-order events, clock skew, multi-device sessions, mock GPS/spoof signals, adversarial bids.
R09-03 observability, SLO and incident playbook, staging smoke tests, Android builds and real low-network field tests, rollback plan.
R09-04 pilot 50 verified drivers then 100; gradual districts and rider acquisition; legal gate before paid public service.

## S10 Growth [P1/P2]
R10-01 referrals only after completed qualifying rides [P1]; promo/priority vouchers with abuse limits [P1].
R10-02 scheduled rides, airport, hotel and corporate accounts/invoicing [P1/P2].
R10-03 multi-city rollout tooling (data model is multi-city/multi-tenant from MVP per D017), wallets and enhanced price learning [P2].
R10-04 Future SaaS [P2]: self-service tenant onboarding, SaaS operator subscriptions/billing (separate from driver subscriptions), white-label branding, tenant data export/offboarding, public API/webhooks. See ../PRD.md.

## Explicit exclusions from MVP
No direct cash fines, no stored rider payment cards, no arbitrary private-car activation, no guaranteed offline bidding, no automatic punishments from a single GPS point or star rating, no 'buy higher trust' feature.
