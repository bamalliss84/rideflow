# RideFlow — Open Decisions (owner approval required before related code)
Version 0.1 | 2026-10-21 | None of these block documentation; items marked ⛔ block the named task.

> Update 2026-10-21 (Phase 1): OD-01, OD-03, OD-04 (backend) and D012 were resolved by the owner. See 06_DECISION_LOG D020–D027. Phase 1 uses the proposed defaults for the remaining items, as tenant-configurable parameters marked PROPOSED/PROVISIONAL (GET /api/v1/admin/config). These are not approved policy.

| ID | Question | Proposed default | Blocks |
|---|---|---|---|
| OD-01 | ~~Identity across tenants~~ **RESOLVED (D022):** one global identity with per-tenant memberships | — | — |
| OD-02 | Trust Score / ratings / violations: per tenant or shared across tenants? | Per tenant only (privacy, isolation). **Implemented as the default in Phase 1**; owner confirmation still requested | T04-A |
| OD-03 | ~~How does an app know its tenant~~ **RESOLVED (D023):** trusted application context (registered app client id), white-label ready | — | — |
| OD-04 | ~~Stack approval~~ **RESOLVED for backend (D020)**; Flutter apps planned for later phases (D025) | — | — |
| OD-05 | Can a driver work for multiple tenants simultaneously? | No in MVP (separate accounts allowed, not linked) | T01-B |
| OD-06 | Per-city overrides inside a tenant config? | Tenant-level only in MVP | T02-A |
| OD-07 | Retention periods for location, documents, audit | To define with legal review | T03-B |
| OD-08 | Behavior when a tenant is suspended | Block new requests; active trips finish; data retained | T08 |
| OD-09 | Platform admin break-glass procedure | Reason + time-boxed + audited | T01-A |
| D009 | Driver subscription price/trial | 5,000 YER/month, 60-day founder trial | T05-A |
| D010 | Wait time / geofence | 5 min / 200 m | T03-B |
| D011 | Trust weights, tiers, discount | See 02_BUSINESS_POLICY | T04-A |
| D012 | ~~Driver reconfirmation after rider selection~~ **RESOLVED (D027):** confirmation required; timeout is tenant policy | — | — |
| D013 | Legal permits, insurance, registration (Hadramout) | Legal review — release blocker | G0 |
| D014 | Deposit account/provider, settlement evidence | Open | T05-A |
| D015 | Compensation rate, caps, expiry, appeal window | Open | T04-A |
| D016 | CI host and staging resources | GitHub Actions proposed | T00-C |
| OD-10 | Windows toolchain: install/verify Flutter, Python, Docker Desktop, PostgreSQL client | Verify before T00-C | ⛔ T00-C |
