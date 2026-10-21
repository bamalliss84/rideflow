# ADR-0001 Multi-tenancy: shared database, tenant-scoped records
Status: ACCEPTED (D017) | 2026-10-21
Context: RideFlow is SaaS for independent operators; pilot is one tenant.
Decision: Single PostgreSQL database, `tenant_id` on all operational tables, tenant from auth token, tenant-aware data layer failing closed, composite FKs, PostgreSQL RLS as second line, tenant-namespaced caches/files/channels, mandatory isolation tests.
Alternatives: schema-per-tenant (stronger separation, heavy migrations at scale); database-per-tenant (best isolation, highest ops cost). Rejected for MVP cost/ops; may be offered later for large tenants.
Consequences: every query and test must carry tenant context; RLS requires per-transaction setting with pooled connections.
