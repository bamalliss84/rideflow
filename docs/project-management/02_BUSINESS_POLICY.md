# BUSINESS POLICY — versioned proposals; OWNER APPROVAL REQUIRED
Policy values below are starting hypotheses, not finalized local legal or commercial terms.
Per D017, every numeric value, currency and rule parameter here is tenant-configurable; the values below are the proposed defaults for the Mukalla pilot tenant. Rules themselves (bidding, no fines, evidence, appeals) apply to all tenants.

## Bid and price contract
Estimated fare range informational. Drivers propose binding amount for stated pickup/dropoff; rider chooses and driver confirms (final confirmation policy may be streamlined after usability tests). Lock price after atomic confirmation. Any route/price amendment needs explicit bilateral acceptance and audit trail. Drivers need not bid; riders need not choose.

## Cancellation matrix
Before match: no violation. Within first 2 minutes of match: proposed free cancellation (exceptions for abuse). After departure: record event; repeated proven late cancellations affect commitment. At arrived: evaluate late cancellation with GPS uncertainty and notice delivery. No-show only after minimum 5-minute wait, valid geofence (proposed 200m, adjusted for accuracy), and evidence of contact attempt/notification; allow appeal. Apply symmetric protections when driver fails to arrive or abandons accepted trip. Never use a single location fix to prove guilt.

## Enforcement ladder (rolling 30 days; suggested)
1 verified incident: education/warning; 2: commitment score effect and warning; 3: temporary request/offer restriction up to 24h after review; 4+: up to 72h/manual review. Severe safety incidents require immediate human escalation; repeat offenders can be restricted subject to appeal. Auto-rules only for low-risk reversible measures, with evidence and override.

## Trust model
Keep stars and objective commitment distinct. Suggested driver score weights: rider ratings 30%, completed matches 20%, accepted-trip cancellation 20%, punctuality 10%, substantiated complaints 10%, positive conduct 10%. Suggested rider weights: driver ratings 25%, attendance 30%, late cancellations 20%, agreed-price compliance 15%, substantiated complaints 10%. Use Bayesian smoothing and confidence label; do not expose precise private user data. Thresholds and weight changes must be versioned and validated for bias/gaming. Bronze/silver/gold/diamond are display tiers, not evidence of legal safety certification.

## Rewards and compensation
Proposed 10–15% renewal discount for consistently verified high-commitment drivers, not simply paid plan. Verified no-show compensation as subscription credit/day, with monthly cap per driver and total program budget, fraud review and no cash redemption. Examples in previous study (20 points, 100 points for 3 days etc.) are mutually unvalidated proposals; DO NOT implement contradictory exchange rates. Owner must approve one rate and cap first. Rider restitution can be noncash service priority, subject to fairness.

## Subscription
Proposed 5,000 YER/month, founder 60-day trial for first 100 approved drivers, optional 8,000 YER pro and 1,500 YER weekly later. Validate driver willingness and current purchasing power before fixing price. Payment by deposit to the tenant's (operator's) business account — for the pilot tenant, the owner's account (D003); screenshot alone not proof of funds. Admin independently reconciles statement/reference before activation; duplicates rejected; 2-person approval preferred where staffing permits. Cash trip payment directly from rider to driver; app records declaration, not escrow.

## Disputes and privacy
Trip evidence: actor, event, timestamp from server, optional device timestamp, coarse/relevant location and accuracy, notification delivery, call initiation metadata (not recording), route amendments and bids. Role-restricted access, defined retention, no public exposure of rider exact addresses, appeal process and corrections. No financial penalties without legally reviewed payment collection mechanism and consent.
