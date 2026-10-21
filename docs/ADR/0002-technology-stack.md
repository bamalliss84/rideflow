# ADR-0002 Technology stack
Status: ACCEPTED for the backend (D020, 2026-10-21; Windows toolchain verified). Admin: future React/Next.js dashboard, with Django admin for internal technical use only (D024). Flutter apps come in later phases (D025).
Decision: Flutter (rider, driver), Django + DRF + Channels, PostgreSQL/PostGIS, Redis, Docker Compose for dev, admin initially Django admin/dedicated web if justified.
Alternatives: Node/NestJS backend; Supabase/Firebase (weaker control of isolation/RLS and offline semantics); FastAPI (less built-in admin/auth).
Consequences: Python + Flutter + Docker required on dev machine.
