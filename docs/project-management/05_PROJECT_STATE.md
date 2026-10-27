# PROJECT STATE — UPDATE AFTER EVERY SESSION

| | |
|---|---|
| Updated | 2026-10-22 |
| Project | RideFlow, a multi-tenant ride-hailing SaaS (first pilot city: Mukalla, Yemen) |
| Status | PHASE 2 ADMIN PORTAL IMPLEMENTED AND VERIFIED LOCALLY (on top of the Phase 1 backend). Not declared complete; open items in docs/reports/PHASE_02_ADMIN_REPORT.md §7 |
| Repository URL | https://github.com/bamalliss84/rideflow.git |
| Local path | D:\projects\rideflow |
| Default branch | main |
| Last accepted task | T00-B (documentation baseline). Phase 1 is awaiting owner review |
| Current task | Phase 2 admin portal: delivered, pending owner design and reviewer acceptance |
| Phase 1 implementation commit | `0da382308386677be1ddc490314cbd18b5a06656` |
| Phase 2 implementation commit | `daefc54c93fb7eb915dd752bb1f130351a4371bb` |
| Admin portal (local) | http://localhost:3000 |
| Last passing CI run | NONE observed yet. The workflow is committed and its identical steps pass locally |
| Staging URL | NONE |
| Production URL | NONE |

## Implemented

**Phase 2 (2026-10-22):**

- `apps/admin`: Next.js admin portal with a platform portal (overview, operators, provisioning, apps, administrators, audit) and an operator portal (dashboard, drivers and verification queue, riders, rides, live drivers, cities and zones, subscriptions, trust and safety, reports, notifications, audit, members, policy, organization).
- Session security: BFF with HttpOnly cookies and CSRF protection.
- Mandatory TOTP MFA for administrators (backend).
- Docker service `admin` on port 3000.
- See docs/reports/PHASE_02_ADMIN_REPORT.md and ADR-0005.

**Phase 1:**

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
- (Resolved 2026-10-27) Docker restored; Phase 3 final build and full E2E run passed (25/25).

- Legal and transport approval (G0) is not verified.
- Admin MFA and the production adapters (SMS, push, upload scanning) are missing before any shared environment.
- No pricing data.

## Local development login (D033, 2026-10-22)

`DEV_ADMIN_MFA_BYPASS` lets admin logins skip TOTP in the local Docker stack only. OTP and password are still required, and production MFA is unchanged.

**Applied:** the local stack was rebuilt on 2026-10-24 after the system clock was corrected; the dev bypass is active in Docker. Commit: `89fe588`.

## Phase 3: QA and security hardening (2026-10-25), CONDITIONAL PASS

Reports: `docs/reports/PHASE_03_QA_REPORT.md`, `PHASE_03_DEFECT_REGISTER.md`, `PHASE_03_RELEASE_READINESS.md`.

**Fixed (8 defects, all with regression tests):**
- P3-01 (high): spoofable `X-Forwarded-For` throttles / platform-login brute force.
- P3-02 (high): weak production secret key.
- P3-03: required MFA encryption key.
- P3-04: Redis outage now 503.
- P3-05: N+1 in four admin lists.
- P3-06: HSTS on, API docs hidden in production.
- P3-07: proxy dot-segment guard.
- P3-08: E2E session files excluded from Docker images.

**Added:**
- Administrator MFA recovery codes (D034).
- Playwright E2E suite (25 tests, `cd apps/admin && npx playwright test`, dedicated `e2e-qa` tenant via `manage.py seed_e2e`).
- `scripts/perf_smoke.py`.

**Tests:**
- Backend: 144 passed.
- tsc/eslint: clean.
- E2E: 24/25 full run, and the remaining failure (per-phone OTP limit, fixed in the harness) passed on re-run (8/8 auth).

**Final verification (2026-10-27):** production build and full E2E run 25/25 passed; CI success on `1cbc333`.

**Release blockers** (production server, SMS, malware scanning, maps, legal, owner policy approval, proxy config) are listed in the release-readiness report.

## Dashboard final review (2026-10-24)

Refinement of the existing platform and operator portals to the approved visual direction. See `docs/reports/PHASE_02_DASHBOARD_FINAL_REVIEW.md`.

**Fixed:**
- tab-strip scroll arrows;
- phone-width page overflow from escaping hidden table labels;
- grid blow-out;
- bidi-broken mixed strings and scrambled Arabic dates and amounts.

**Pages:**
- localized audit log;
- notifications with read/unread;
- sectioned policy editor with validation and unsaved-changes guard;
- honest zero-filled report chart;
- ratings filters;
- dispute decision layout;
- organization grid.

**Backend:** notification feed `read` flag plus single-item mark-read; contract regenerated.

**Tests:** full backend suite 126 passed; tsc and eslint clean; production build ok; browser smoke on every operator route at 375px and on selected routes at 768/1280/1440px.

## Test evidence, Phase 2 (2026-10-22)

- **Backend:** `pytest --create-db` 113 passed; ruff clean; no migration drift; OpenAPI valid (135 paths).
- **Frontend:** `tsc` 0 errors; `eslint` 0 findings; `next build` ok (41 routes).
- **Docker:** compose up with admin returns 200 on `/login`.
- **Browser walkthrough** of the sign-in with MFA and the critical workflows: see report §5.

## NEXT CLAUDE PROMPT (Phase 3 candidates)

1. Confirm GitHub Actions is green, including the new admin job.
2. Add Playwright E2E for admin sign-in, verification, deposit and dispute flows.
3. Add MFA recovery codes.
4. Start the Flutter rider app on the frozen contract.

Owner input is needed on: design acceptance, map provider, and the PROPOSED/PROVISIONAL policy values.

## NEXT CLAUDE PROMPT (Phase 1, historical)

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
| 2026-10-21 | Phase 1 backend | main / `0da382308386677be1ddc490314cbd18b5a06656` | repo foundation + services/api + tests + docs | 103 passed; lint/format/migrations/OpenAPI ok; live smoke ok | pending | fixed during session: FOR UPDATE on outer join, django-filter class-level queryset vs fail-closed manager, OTP per-IP limit too strict | D020–D028 | Phase 2 (MFA, CI green, Next.js scaffold) |
| 2026-10-22 | Phase 2 admin portal | main / `daefc54c93fb7eb915dd752bb1f130351a4371bb` | apps/admin (new), backend MFA + portal endpoints, compose/CI/docs | 113 backend passed; tsc/eslint/build ok; browser walkthrough ok | pending | fixed: refresh-token rotation race (single-flight refresh), django-filter + fail-closed manager, React hook state anti-patterns | D029–D032 | Phase 3 |
| 2026-10-22 | Dev-only admin MFA bypass (D033) | main / `89fe588` | accounts auth/mfa/views, settings, compose, BFF auth route, login screens, tests, docs | focused 47 passed; full 125 passed; tsc/eslint/build ok; live API check on :8011 ok | pending | admin image rebuild blocked by system clock (TLS CERT_NOT_YET_VALID) | D033 | sync clock, rebuild |
| 2026-10-24 | Phase 2 dashboard final review and UI/UX refinement | main / `0300cb0` | admin shared UI (shell, tables, tabs, cards, chart, bidi helpers, audit labels), 9 refined pages and bidi fixes across others, notifications API read state, contract, tests, docs | backend 126 passed; tsc/eslint 0; docker prod build ok; browser smoke at 375 on all operator routes plus selected 768/1280/1440 | ok | none | — | owner visual review |
| 2026-10-25 | Phase 3 QA and security hardening | main / `c934039` | throttling/proxy trust, production settings, MFA recovery codes, N+1 fixes, Redis 503, E2E suite, perf script, reports | backend 144 passed; tsc/eslint 0; E2E 25 tests (24/25 full run + 8/8 auth re-run); perf smoke 720 req 0 errors | conditional | Docker engine down (C: full) blocks final rebuild and E2E re-run | D034 | free disk, rerun E2E; release blockers R-01..R-10 |

Template: Date/time | Task ID | Branch/commit | Files changed | Tests and outputs | Accepted? | Bugs | Decisions | Next task.
