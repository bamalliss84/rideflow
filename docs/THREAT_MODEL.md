# RideFlow — Threat Model
Version 0.1 | 2026-10-21 | Method: STRIDE-style per asset. Severity follows 04_EXECUTION_AND_QA.md (P0/P1/P2).

| # | Threat | Impact | Mitigations | Sev |
|---|---|---|---|---|
| T1 | Cross-tenant data access (IDOR, forged tenant id, missing filter, cache/channel key collision) | Leak of riders/drivers/trips across operators | Tenant from token only; fail-closed manager; RLS; composite FKs; namespaced Redis/WS/files; isolation test suite | P0 |
| T2 | Platform admin misuse | Silent access to tenant data | Break-glass with reason, time limit, AuditEvent, tenant-visible log | P0 |
| T3 | GPS spoofing / mock location | False arrival or no-show | Accuracy + timestamps + contact evidence; advisory spoof signals; never single fix; human review & appeal | P0 |
| T4 | Fake / duplicate accounts | Fraud, bid manipulation, rating abuse | OTP throttling, device/phone signals per tenant, driver document review | P1 |
| T5 | Duplicate or forged deposit receipts | Free subscriptions, revenue loss | Unique reference + receipt hash per tenant, bank statement reconciliation, maker-checker, screenshot not proof | P0 |
| T6 | Concurrent bid acceptance / double confirmation | Two drivers on one trip, disputes | DB transaction + row lock, partial unique constraints, idempotency keys, expected version | P0 |
| T7 | Network loss, replay, out-of-order events | Duplicate trips, wrong state | Idempotent commands, server timestamps, event cursors, pending-sync UI | P1 |
| T8 | Retaliatory / collusive ratings | Unfair Trust Score | Bayesian smoothing, minimum sample, retaliation detection, no sanction from stars alone | P1 |
| T9 | Compensation credit farming | Credit abuse | Verified events only, caps per driver/tenant, fraud review, ledger | P1 |
| T10 | OTP/SMS abuse | Cost, account takeover | Rate limits per phone/IP/tenant, short expiry, attempt caps | P1 |
| T11 | Malicious uploads | Malware, storage abuse | Type/size caps, scanning, private tenant-scoped storage, signed URLs | P1 |
| T12 | PII / precise location leakage | Privacy harm | Coarse exposure, role + tenant restriction, retention, log redaction | P0 |
| T13 | Token theft / session hijack | Account takeover | Short-lived tokens, revocation, admin MFA, device sessions list | P1 |
| T14 | Price tampering after match | Disputes | Price lock, bilateral signed amendment with audit | P1 |
| T15 | Tenant suspended mid-operation | Stranded trips | Defined suspension behavior: block new requests, allow active trips to finish (OD-08) | P2 |
