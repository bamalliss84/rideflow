# ADR-0003 Money, currency and tenant configuration
Status: ACCEPTED in principle (D017); details PROPOSED
Decision: integer minor units + ISO-4217 per tenant; no floats; no cross-currency math in MVP. Policy parameters in versioned TenantConfig with effective_from; trips/claims store config version used so later changes never rewrite history.
Alternatives: global config (contradicts D017); per-city config only (insufficient — operator-level policy needed). Per-city overrides may be added later.
