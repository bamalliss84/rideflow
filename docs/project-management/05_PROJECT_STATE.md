# PROJECT STATE — UPDATE AFTER EVERY SESSION

| | |
|---|---|
| Updated | 2026-10-21 |
| Project | RideFlow, a multi-tenant ride-hailing SaaS (first pilot city: Mukalla, Yemen) |
| Status | PHASE 1 BACKEND IMPLEMENTED AND VALIDATED LOCALLY. Not declared complete; open items in docs/reports/PHASE_01_BACKEND_REPORT.md §3 |
| Repository URL | https://github.com/bamalliss84/rideflow.git |
| Local path | D:\projects\rideflow |
| Default branch | main |
| Last accepted task | T00-B (documentation baseline). Phase 1 is awaiting owner review |
| Current task | Phase 1 backend: delivered, pending owner and reviewer acceptance |
| Phase 1 implementation commit | `<PHASE1_COMMIT_SHA>` (see `git log`) |
| Last passing CI run | NONE observed yet. The workflow is committed and its identical steps pass locally |
| Staging URL | NONE |
| Production URL | NONE |

## Implemented

`services/api` (Django 5.2 LTS + DRF + Channels, PostGIS, Redis) contains these apps: core, tenancy, accounts, drivers, geo, rides, subscriptions, trust, notifications and backoffice.

The rest of the repository:

- Docker Compose with db, redis, api and worker
- CI workflow
- Windows scripts
- OpenAPI contract in `packages/contracts/openapi.yaml`
- demo seed
- Phase 1 report in `docs/reports/PHASE_01_BACKEND_REPORT.md`

## Test evidence (2026-10-21, local Docker on Windows)

`scripts\test.ps1 -PytestArgs "--create-db -rA"` exited 0:

- ruff check: all checks passed
- ruff format: 118 files formatted
- makemigrations --check: no changes
- pytest: **103 passed**

OpenAPI validates with `--fail-on-warn`. A live HTTP smoke test (including cross-tenant probes) passed.

## Pending decisions

- **Resolved this session:** OD-01, OD-03, OD-04 (backend) and D012. See D020–D027.
- **Still open:** D009, D010, D011, D013 (legal, release blocker), D014, D015, OD-02 confirmation, and OD-05 to OD-09.

## Current blockers

- Legal and transport approval (G0) is not verified.
- Admin MFA and the production adapters (SMS, push, upload scanning) are missing before any shared environment.
- No pricing data.

## NEXT CLAUDE PROMPT

Phase 2, first bounded tasks:

1. Confirm that GitHub Actions CI is green on main and fix any CI-only differences.
2. Implement admin MFA (TOTP) for tenant staff and platform admins, with tests.
3. Scaffold the Next.js admin in apps/admin with a client generated from packages/contracts/openapi.yaml.

Do not change approved policy. Owner approval of the PROPOSED/PROVISIONAL policy values is still required.

## Session log

| Date | Task | Branch/commit | Files changed | Tests and outputs | Accepted? | Bugs | Decisions | Next task |
|---|---|---|---|---|---|---|---|---|
| 2026-10-21 | T00-A | none | none (inspection only) | git status: no commits, docs/ untracked | n/a | - | - | T00-B |
| 2026-10-21 | T00-B | main / no commit | 9 pack files edited + 11 new docs | doc checks only | pending | - | D017–D019 | T00-C |
| 2026-10-21 | Phase 1 backend | main / `<PHASE1_COMMIT_SHA>` | repo foundation + services/api + tests + docs | 103 passed; lint/format/migrations/OpenAPI ok; live smoke ok | pending | fixed during session: FOR UPDATE on outer join, django-filter class-level queryset vs fail-closed manager, OTP per-IP limit too strict | D020–D028 | Phase 2 (MFA, CI green, Next.js scaffold) |

Template: Date/time | Task ID | Branch/commit | Files changed | Tests and outputs | Accepted? | Bugs | Decisions | Next task.
