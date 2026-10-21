# RIDEFLOW — SOURCE OF TRUTH
Version 1.1 | 2026-10-21 | Status: PLANNING, NOT IMPLEMENTED

RideFlow is a multi-tenant ride-hailing SaaS. A tenant is an independent transportation operator that may operate in multiple cities. Mukalla, Yemen is the first pilot city, not a product limitation (D017).

## Roles
Owner approves business decisions and costs; ChatGPT specifies, reviews, and decides acceptance based on evidence; Claude Code implements locally. Neither assistant can assume work completed without artifacts and tests.

## Product invariants
Mukalla first pilot city; strict tenant isolation; tenant-specific currency, pricing, cancellation rules and configuration; rider gets indicative range, solicits competing driver offers, selects offer and confirms match; driver paid cash by rider; driver pays platform subscription via manually reviewed deposit; no per-ride commission in MVP; weak-network-first; both sides rated; provable violations, human appeal and proportional penalties; legally eligible drivers/vehicles only.

## Read order for any new conversation or Claude session
1. This file 2. 01_MASTER_ROADMAP.md 3. 02_BUSINESS_POLICY.md 4. 03_ARCHITECTURE_AND_API.md 5. 04_EXECUTION_AND_QA.md 6. 05_PROJECT_STATE.md 7. 06_DECISION_LOG.md 8. 07_FINANCIAL_VALIDATION.md 9. 08_STRICT_CLAUDE_MASTER_PROMPT.md 10. 10_ORIGINAL_PHASE_00.md (historical). Phase 00 baseline: ../PRD.md, ../BUSINESS_RULES.md, ../ARCHITECTURE.md, ../DATA_MODEL.md, ../ADR/, ../THREAT_MODEL.md, ../TEST_PLAN.md, ../OPEN_DECISIONS.md.

## Golden rules
No undocumented scope change; no production secrets; no invented test results; no code without tests; no live deployment without approval; no monetary no-show fines in MVP; ratings are not proof; GPS alone is not proof; preserve backwards compatibility; protect user PII and precise location; never silently change approved policy. Legal review with local transport authorities is a release blocker.

## Fast restart prompt
Read all docs in this directory and inspect the repository state. Summarize current commit/branch, last accepted sprint, pending blockers, actual test evidence, and the next smallest executable task. Do not assume earlier chat content is authoritative over files and git. Propose a bounded patch, then await approval if it affects business policy, schema migrations, external integrations or deployment.
