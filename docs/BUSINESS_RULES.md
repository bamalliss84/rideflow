# RideFlow — Business Rules
Version 0.1 | 2026-10-21 | Tags: **[APPROVED Dxxx]** or **[PROPOSED Dxxx]**. Proposed values are tenant-configurable defaults for the Mukalla pilot tenant (D017). Detailed policy: project-management/02_BUSINESS_POLICY.md. Nothing here changes an approved rule.

## 1. Tenancy [APPROVED D017]
- Every rider, driver, vehicle, request, bid, trip, rating, violation, dispute, subscription, deposit and ledger entry belongs to exactly one tenant.
- No object may reference an object of another tenant. No cross-tenant visibility of users, trips, scores or documents.
- Trust Score, ratings and violations are computed per tenant [PROPOSED — see OPEN_DECISIONS OD-02].
- Tenant-configurable: currency, time zone, cities/zones, fare guide, bid expiry, dispatch wave size/radius, cancellation windows, wait time, geofence, enforcement thresholds, trust weights, tiers, discounts, compensation rate/cap, subscription plans and deposit accounts.

## 2. Request, bid and match [APPROVED D004]
States: REQUESTED → BIDDING → MATCH_PENDING → ASSIGNED → EN_ROUTE → ARRIVED → IN_PROGRESS → COMPLETED; terminal/branch: CANCELLED, NO_SHOW, DISPUTED. Only listed transitions by authorized actor; server timestamps authoritative.
- Indicative range is informational, labeled "estimate, not guaranteed".
- Request sent in staged waves to eligible available drivers of the same tenant and city [PROPOSED 5–10 per wave].
- Rider may propose an optional price. It must not be below a percentage of the start of the indicative range, set by each operator (default 100%, shown rounded to a whole unit); it has no maximum and cannot be changed after the request is sent (cancel and request again). It is not shown to the rider as guaranteed until a driver accepts. Without one, drivers see the indicative range; with one, they see it clearly beside the range. A driver may offer their own price, not limited by the rider's price or the range; no price is final until the rider selects and the driver confirms [D035, owner review pending, not implemented].
- Driver bid = binding amount for stated route, with expiry. Rider selects; driver reconfirmation [OPEN D012].
- Confirming a ride withdraws the driver's open offers on other rides [D037].
- One active match per request; one active trip per driver; price locked at match; amendment only with bilateral acceptance and audit.
- No penalty for not bidding or for rider declining all bids.
- A driver may hide a request from their own list, with no penalty and no effect on anyone else; saved on the server [D035, not implemented].

## 3. Cancellation and no-show [APPROVED principle D006; values PROPOSED D010]
- Before match: free. First 2 minutes after match: free (abuse exceptions).
- After departure / at arrival: recorded; repeated proven late cancellations affect commitment.
- Rider no-show only if: wait ≥ 5 min, arrival inside geofence (200 m adjusted for accuracy), contact/notification attempt evidence; appealable. Never a single GPS fix.
- Symmetric protections for driver no-arrival or abandonment.

## 4. Ratings, Trust Score, tiers [APPROVED D006; weights PROPOSED D011]
- Bilateral 1–5 stars with reason tags; Bayesian smoothing, minimum sample, show sample count.
- Trust Score separates subjective stars from objective commitment. Proposed weights in 02_BUSINESS_POLICY.md.
- Bronze/silver/gold/diamond are display tiers; paid plans cannot buy trust or hide violations.
- No automated sanction from stars alone.

## 5. Enforcement [PROPOSED D011]
Rolling 30 days: 1 warning; 2 commitment effect; 3 up to 24 h restriction after review; 4+ up to 72 h / manual review. Severe safety → human escalation. Auto-rules only low-risk, reversible, evidence-backed, overridable. No monetary fines in MVP [APPROVED].

## 6. Compensation [APPROVED principle; rate/cap OPEN D015]
Verified rider no-show → driver credit as subscription days/credit, capped per driver and per tenant budget, no cash redemption, fraud review, ledger entry.

## 7. Cash payments [APPROVED D002]
Rider pays driver in cash; app records declaration and acknowledgment; platform/tenant holds no custody.

## 8. Driver subscriptions [APPROVED D003; prices PROPOSED D009]
- Driver pays the operating tenant by bank deposit; uploads receipt and unique reference; screenshot is not proof.
- Tenant admin reconciles against statement (maker-checker preferred); duplicate hash/reference rejected; activation, expiry, grace via immutable ledger.
- Driver subscriptions are distinct from future SaaS operator subscriptions (tenant → RideFlow) [APPROVED D017]; separate entities and ledgers.

## 9. Disputes and privacy [APPROVED D006]
Evidence with provenance, reviewer audit trail, appeal window, manual override with reason. Role-restricted, tenant-restricted access; defined retention; no exact rider address exposure.

## 10. Abuse prevention
OTP throttling, duplicate account signals per tenant, mock-location signals (advisory), bid spam limits, retaliation-rating detection, deposit duplicate detection.
