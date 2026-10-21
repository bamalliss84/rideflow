# FAST EXECUTION SYSTEM — CLAUDE CODE / CHATGPT

## Sprint structure
Work in vertical slices with demonstrable behavior. Limit each Claude task to 1–3 closely related acceptance criteria and preferably <=1 day of engineering. Parallelize only independent modules with locked OpenAPI contracts; avoid simultaneous edits to migrations, shared models or state machine.

## First 12 task cards
T00-A environment inspection, versions, repo and docs, no application logic.
T00-B architecture and documentation baseline incl. multi-tenancy (D017) — renumbered by owner 2026-10-21.
T00-C docker-compose PostGIS/Redis, env sample, health checks, CI (formerly T00-B).
T01-A tenant model + user/roles/OTP fake adapter, tenant-scoped auth and isolation tests.
T01-B driver/vehicle onboarding, document validation and admin queue.
T02-A service zones + fare estimate adapter and tests.
T02-B request + staged dispatch and driver availability.
T02-C bid create/expiry/list + rider selection race tests.
T03-A match/driver confirmation and trip state machine.
T03-B arrive/wait/cancel/no-show evidence (no automatic punishment).
T03-C trip start/complete/cash declaration/receipt.
T04-A ratings, commitment metrics, disputes and appeals.
T05-A plans, deposit claims, reconciliation, ledger and tests.
Then Flutter apps consume frozen OpenAPI schemas, admin reporting, field tests and deployment hardening.

## Definition of Done per task
Feature ID + acceptance cases; migration and rollback notes; API schema updated; automated unit/integration tests; lint/static checks; screenshots/video for UI; no regression in ride lifecycle; security/PII review; test command with actual exit status; changed file list; risks and unresolved decisions. No 'done' without reproducible proof.

## Claude output contract
1 Task ID and branch/commit; 2 implemented behavior and exclusions; 3 files changed; 4 DB migrations; 5 exact test commands and results; 6 manual QA steps; 7 security/privacy impacts; 8 unresolved blockers; 9 next suggested small task. Do not make unsupported success claims.

## Review severity
P0 blocker: lost/duplicated trip, money/subscription incorrect, unauthorized access, leakage, fabricated GPS guilt. P1 blocker: inability to finish primary rider/driver flow or broken offline recovery. P2: cosmetic and low-risk polish. ChatGPT may recommend approval; owner approves release and spending.

## CI gates
Backend unit+integration, migration consistency, format/lint, Flutter analyze/test, OpenAPI compatibility, secret scan, Docker smoke. Run critical state-machine concurrency tests before merge. Deploy to staging only from tagged tested commits; rollback plan and DB backup required.

## Time savings
Use generated API clients from OpenAPI; shared design tokens; mocked map/SMS/push in dev; fixtures for Mukalla areas; reusable test factories; one-command local bootstrap; short feedback loops; nightly regression optional; track task WIP=1 per shared module. Do not shortcut tests or legal gate.

## Handoff procedure after EVERY sprint
Update 05_PROJECT_STATE.md and 06_DECISION_LOG.md; attach latest git commit and exact tests; include 'NEXT CLAUDE PROMPT' for next bounded task. New chat reads files plus git diff before changing code. If state file conflicts with git/tests, trust actual repository and report discrepancy.
