# Phase 2 — Administration Portal Report

| | |
|---|---|
| Date | 2026-10-22 |
| Branch | `main` |
| Implementation commit | `daefc54c93fb7eb915dd752bb1f130351a4371bb` |
| Local URL | **http://localhost:3000** (operator sign-in at `/login`, RideFlow staff at `/platform/login`) |
| Start | `powershell -ExecutionPolicy Bypass -File scripts\dev-up.ps1 -Build -Seed`, or `docker compose up -d --build` |
| Status | **The portal is implemented, integrated with the real API and verified locally. Phase 2 is not declared complete** until the items in §7 are reviewed (CI first run on GitHub, MFA recovery codes, a real map/SMS provider, owner design acceptance). |

## 1. Summary

`apps/admin` is a Next.js 16 App Router application (TypeScript strict, Tailwind CSS 4) with 41 routes:

- a **platform super-admin portal**;
- a **transport operator portal**, Arabic-first (RTL) with English (LTR).

How it is built:

- **Real data only.** Every screen reads and writes the real Django `/api/v1` through a same-origin BFF. There is no mock data and no hard-coded operational figure.
- **Phase 1 MFA gap closed.** Administrator MFA (TOTP) is now mandatory on the backend, and staff privileges require an MFA-verified session.

## 2. Screens and workflows

### Platform portal (`/platform`)

- **Overview:** operator counts by status, registered apps, platform admins, operators created per month (chart), and a per-operator aggregate table. It shows counts only, never operator records.
- **Operators:**
  - list with a status filter;
  - create/provision: name, slug, ISO currency, minor units, time zone, language; the three white-label app ids are created automatically;
  - operator detail: edit profile (currency is locked), suspend/reactivate (with confirmation), applications (list and register, copyable client id), operator administrators (list with MFA state, add owner/admin, reset authenticator).
- **Platform audit:** platform actions and staff sign-ins.
- **My account:** display name, MFA state, sign-out.

### Operator portal (`/operator`)

Menus follow the role (owner, admin, reviewer, finance, support).

- **Dashboard:**
  - live counters: open requests, awaiting driver, on trip, open bids;
  - period KPIs for today, 7, 30 or 90 days: requests, matched, completed, cancelled, no-shows, agreed cash fares (labelled as declarations, not revenue);
  - daily chart, performance rates and median timings;
  - driver supply;
  - work queues with deep links.
- **Drivers:**
  - list with status tabs, search, online filter and pagination;
  - driver detail: profile, documents with secure preview, expiry highlighting and approve/reject, vehicles with approve/reject, approve/reject/suspend/reinstate (reason required where the API requires it), recent rides, subscriptions, trust profile;
  - **verification queue**: applications, pending documents and pending vehicles on one page.
- **Riders:** searchable list with ride counters, plus detail with trust profile, pending incidents and recent rides.
- **Rides:**
  - explorer filtered by status group, city, rider phone and driver/rider deep links;
  - ride detail: parties, fare (agreed or estimate), timeline of every event, bids, location evidence, schematic route preview, cancellation and no-show evidence, cash confirmations.
  - Admins cannot change ride state (backend contract, stated in the UI).
- **Live drivers:** online drivers with a fresh location around a city centre, shown on a schematic preview and in a table, refreshed every 20 seconds.
- **Cities & zones:** create and edit cities; create and edit coverage zones from GeoJSON or a rectangle helper, with a live preview.
- **Subscriptions:**
  - deposit-receipt queue and review: receipt preview, approve/reject;
  - maker-checker aware: the first or final approval is shown, and the same approver is blocked;
  - plans (create/edit, price typed in major units and stored exactly in minor units);
  - deposit accounts;
  - driver subscriptions (current, upcoming or ended);
  - ledger with CSV export.
- **Trust & safety:**
  - disputes (status tabs, safety flag, detail with case notes and uphold/reject with optional violation);
  - violations (verify/dismiss with a required reason, readable evidence);
  - penalties (activate restrictions, revoke);
  - appeals (uphold/reject, different-reviewer rule enforced by the API);
  - trust scores;
  - ratings with localized tags.
- **Reports:** rides by day (chart, table, CSV) and subscription deposits by status and plan.
- **Notifications:** staff work notifications with deep links, and mark-all-read.
- **Activity log:** the immutable audit trail, filtered by action prefix.
- **Members & roles:** staff, driver and rider tabs; add member (owner role only for owners); suspend/reactivate; reset authenticator.
- **Policy settings:** grouped policy parameters with APPROVED/PROPOSED/PROVISIONAL badges and typed editors. Saving creates a new version after a diff confirmation, and the version history is shown. The page is read-only for roles without `config.manage`.
- **Organization** (read-only) and **My account**.

## 3. Design system

- **Identity:**
  - an original RideFlow mark (route between pickup and drop-off) and wordmark, drawn in SVG code;
  - tokens defined in `src/app/globals.css`: navy `#10243A`, teal `#0D9488`/`#0F766E`, surface `#F5F7FA`, amber `#E9A23B`, coral `#E45858`, each with contrast-checked text pairings.
- **Typography:** IBM Plex Sans Arabic for both Arabic and Latin, self-hosted by `next/font`, with system fallbacks. Tabular numbers are used.
- **Components:**
  - buttons, badges, cards, key/values, stat cards, form fields with inline errors, switch;
  - native `<dialog>` modals and confirmation dialogs (the confirm button is disabled while busy, the reason is validated);
  - data table (skeleton, empty and error states, responsive column hiding), pagination, tabs, search with debounce, filter selects, range picker;
  - toasts, CSS bar chart, rate bars, SVG geo preview.
  - Icons are lucide only.
- **RTL/LTR:** logical properties throughout, and direction-aware chevrons and arrows. Language switches via a cookie and `<html lang dir>`. Arabic UI uses Latin digits for phones, amounts and IDs (D032).
- **Responsive:** sidebar on desktop, drawer below `lg`. At a 375 px phone width no element overflows the viewport (checked).
- **Formatting:** dates in the operator time zone; currency from integer minor units with the operator currency; relative times and units localized with `Intl`.

## 4. Backend changes in this phase (minimal; D030, D031)

| Change | Why |
|---|---|
| `MFADevice` model and migration; `/auth/mfa/setup` and `/auth/mfa/verify`; the first factor for admin app and platform returns a challenge; token claim `mfa`; staff roles dropped without it; platform scope refused without it | Close the Phase 1 MFA gap (R01-04, T13) |
| Dev OTP adapter refuses to start unless `DJANGO_DEBUG=1` | Never expose dev OTPs in production |
| `/auth/app-context` (public: operator name, app type, locale, status) | Login screen shows which operator you sign in to |
| `/admin/riders` (list/detail), `/admin/ratings` | Riders and ratings screens |
| `/platform/overview` (aggregates only), `/platform/audit-events`, `GET /platform/tenants/{id}/admins`, platform and member MFA reset | Platform portal and lost-device recovery |
| Read-only `*_name` fields on admin serializers; `live` block on dashboard metrics | Human-readable labels instead of raw IDs; live operations |
| Staff notifications for submitted drivers, deposits, disputes, appeals and incidents | Notifications page lists real work items |
| Member `role` filter accepts multiple values; driver `q` search | Correct pagination for the staff tab; search |

RLS, tenant resolution, the state machine and business policies are unchanged. The isolation route test was extended to the new routes.

## 5. Checks actually run (2026-10-22, local Windows + Docker)

| Check | Result |
|---|---|
| Backend `ruff check`, `ruff format --check` | passed (120 files) |
| `makemigrations --check` | no changes |
| Backend `pytest --create-db` | **113 passed** (103 from Phase 1 + 10 new MFA/portal-API tests) |
| OpenAPI `spectacular --validate --fail-on-warn` | ok, 135 paths, exported to `packages/contracts/openapi.yaml` |
| Frontend `tsc --noEmit` (strict) | 0 errors |
| Frontend `eslint --max-warnings=0` (next core-web-vitals + typescript) | 0 findings |
| Frontend `next build` | success, 41 routes |
| `docker compose build admin` and `docker compose up -d`; `scripts\dev-up.ps1` | ok; http://localhost:3000/login returns 200 |
| HTTP probes | `/` without a session redirects to `/login`; `/operator/*` redirects to `/login?next=…`; proxy without session returns 401; cross-origin POST returns 403 `csrf_failed`; CSP and `X-Frame-Options: DENY` present |

Browser walkthrough in the built-in browser against the running stack, operator portal (Arabic):

- **Sign-in:** workspace resolved to the operator name, OTP, authenticator enrolment (QR and manual key), TOTP verification, then the dashboard with real figures.
- **Session storage:** script-visible cookies were only `rf_ws` and `rf_csrf`; local and session storage were empty.
- **Verification queue:** document preview (private blob), document approve dialog, list refresh; three more approvals; the driver approved; suspend without a reason was blocked client-side.
- **Deposits:** a 5,000 YER receipt reviewed and approved; the subscription and ledger appeared.
- **Disputes:** a case note was added; the case was resolved as rejected with a reason.
- **Language:** English/LTR switch worked.
- **Policy:** the bid validity was changed from 120 to 150, saved as version 2 with a diff confirmation.
- **Page crawl:** every operator page rendered with data.
- **Portal separation:** sign-out cleared the session; an operator session opening `/platform/*` was redirected to `/operator`.

Browser walkthrough, platform portal:

- **Sign-in:** password, authenticator enrolment, TOTP, then the overview with aggregates.
- **Provisioning:** an operator was created through the form; its three apps were auto-registered.
- **Isolation:** a platform session got 403 on `admin/rides/{id}` and `admin/drivers` through the BFF; the proxy refused `auth/*` with 404.
- **Session renewal:** after the 15-minute access token expired, the page loaded through the single-flight refresh.
- **Mobile:** 375 px viewport with no horizontal overflow and the drawer navigation.

Not run in this phase: automated browser E2E tests (Playwright), a screen-reader audit, cross-browser testing, and load testing.

## 6. API coverage

Every operator and platform admin endpoint in the contract is used by a screen. The exceptions, by design, are the rider and driver app endpoints and `admin/config/versions/{id}`.

## 7. Known gaps / remaining items

- **CI:** the new `admin` job and the updated workflow have not yet been observed on GitHub. The same steps pass locally.
- **MFA:**
  - no recovery codes, and no WebAuthn;
  - reset of platform-admin MFA is only possible via Django admin (internal).
- **Maps:** schematic SVG previews only; no street basemap until a map provider is chosen (privacy and cost decision). Zone drawing is GeoJSON or rectangle, not freehand.
- **Not available in the backend, so not shown:**
  - tenant branding (logo and colours);
  - admin-side ride interventions (by design);
  - full driver names on bids (bids carry the privacy-preserving first name);
  - a notification unread badge.
- **Realtime:** the admin uses polling for the dashboard and live drivers; there is no WebSocket for staff yet.
- **UI scope:** light theme only.
- **Test automation:** no automated UI tests yet.
- **Release blockers carried over from Phase 1:** legal gate G0 (D013), policy values pending owner approval, production adapters (SMS, push, upload scanning).

## 8. Phase 3 readiness

- **Ready:** the API contract and typed client pattern (`npm run gen:api`), the BFF/session model and the design system can be reused for any further web surface.
- **Recommended next steps:**
  1. Confirm CI is green.
  2. Add Playwright E2E for the sign-in, verification, deposit and dispute flows.
  3. Add MFA recovery codes.
  4. Get owner design acceptance.
  5. Choose a map provider.
  6. Start Flutter rider and driver apps on the same contract.

## 10. Change 2026-10-22: local-development admin login without TOTP (`DEV_ADMIN_MFA_BYPASS`, D033)

**Design.** Production MFA is unchanged.

- **Backend setting.** `DEV_ADMIN_MFA_BYPASS` defaults to off. `apps.accounts.mfa.dev_bypass_active()` is evaluated on every request and requires all of:
  - `DEBUG`;
  - `RIDEFLOW_ENV == "local"`;
  - only local `ALLOWED_HOSTS`.

  Settings refuse to load when the flag is set without DEBUG and RIDEFLOW_ENV=local.
- **Login.** The first factor is unchanged: OTP through the existing dev OTP provider, or the platform password. When the bypass is active, the login returns tokens with the claim `mfa_dev` and `dev_mfa_bypass: true`, with no challenge and no QR code. No MFA secret is created, read or reset.
- **Authentication.** Staff roles and the platform scope are granted when the token has `mfa`, or has `mfa_dev` **and** the bypass is active right now. Turning the flag off therefore revokes existing dev sessions immediately. `/me` reports `mfa.dev_bypass`.
- **BFF.** The BFF sets session cookies for such a response only if the backend flagged it **and** the BFF's own env `DEV_ADMIN_MFA_BYPASS=1` is set; otherwise it refuses (`mfa_not_enforced`, as before). The login screens skip the MFA step only when the BFF returns an established dev session. No frontend-only switch exists.
- **Unchanged:** tenant isolation, roles, CSRF, cookies and audit. Login audit events record `dev_mfa_bypass`.
- **Enabled only in the local dev stack.** `docker-compose.yml` sets `RIDEFLOW_ENV=local` and `DEV_ADMIN_MFA_BYPASS=1` for api, worker and admin. `.env.example` documents it. Production defaults stay off.

**Tests actually run.**

- **New focused tests** in `test_mfa_and_portal_api.py`:
  - operator dev login still requires the OTP, then gets a session without TOTP; no MFA device is created; `/me` reports `dev_bypass`; audit recorded;
  - platform dev login still requires the password;
  - bypass refused for DEBUG off, RIDEFLOW_ENV production or staging, a public host in ALLOWED_HOSTS, or the flag off (5 cases);
  - after the flag is turned off, earlier dev tokens give 401 for operator and platform, and login returns to the MFA challenge;
  - a dev token used with another tenant's app returns 401;
  - settings refuse the flag outside local.
- **Focused suites:** MFA/portal API, auth and tenant isolation, 47 passed. **Full backend suite: 125 passed.** ruff clean.
- **Frontend:** `tsc --noEmit` 0 errors; `eslint` 0 findings; `next build` succeeded on the host.
- **Live backend check:**
  - temporary bypass-enabled API instance on :8011:
    - wrong OTP returns 400;
    - correct OTP issues a session with `dev_mfa_bypass` and opens the dashboard (200);
    - wrong platform password returns 401;
    - platform login issues a session with `dev_mfa_bypass`; overview 200; operator data 403.
  - the same dev token on the main stack (bypass off) returns 401.
  - main stack (:8010, bypass off) still returns MFA challenges.
  - the temporary instance was removed. The existing MFA device was left untouched.

**Not verified / blocker.**

- **Image rebuild blocked.** The `admin` Docker image could not be rebuilt. `npm ci` inside Docker fails with `CERT_NOT_YET_VALID`: the registry certificate is valid from 10:16 UTC while this machine's clock reads 07:02 UTC. Fix the system clock, then run `docker compose up -d --build`. TLS verification was not weakened.
- **No browser check of this flow.** A host-run portal process for that check was denied by the session permission policy.
- **Running stack.** The currently running containers still run the previous configuration (MFA enforced) until that rebuild.

**Commit:** `89fe588`

## 9. Fix 2026-10-22: operator MFA onboarding showed the 6-digit challenge without any QR code

**Symptom.** After the development OTP sign-in, `+967700000001` went straight to the 6-digit TOTP screen, although the owner had never scanned a QR code.

**Investigation.** Evidence came from `MFADevice` rows and the `auth.*` audit events.

- The backend returns `mfa_enrolled = true` only when a **confirmed** `MFADevice` exists.
- The UI (`MfaStep`) chooses between the setup screen and the challenge solely from that flag.
- Both the Demo Owner (`+967700000001`) and the Platform Admin (`+967700000000`) had confirmed devices:
  - confirmed at 2026-10-21T21:09:51Z and 22:52:27Z;
  - audit data `mfa_enrolled_now: true`.
- Those were created by Claude's automated Phase 2 browser walkthrough (§5), using throwaway secrets that were never handed over.

**Root cause.** The seeded demo accounts were left **already enrolled** by the verification walkthrough. It was **not** a frontend routing bug, and it was **not** in seed data: `seed_demo` creates no MFA devices. The application correctly showed the normal challenge for an enrolled account. Contributing gaps:

- no documented development reset procedure;
- the challenge screen gave no guidance for a lost authenticator;
- §5 did not warn that the demo accounts were left enrolled.

**Fix (minimal; no MFA bypass, no change to production behaviour).**

1. `python manage.py dev_reset_mfa <phone> --i-understand`:
   - deletes the user's authenticator only;
   - refuses unless `DJANGO_DEBUG=1`;
   - requires the explicit flag;
   - never shows or regenerates a secret;
   - writes the audit event `dev.mfa_reset`.

   The next sign-in still requires the first factor, and then forces a fresh enrolment that a valid TOTP must confirm.
2. The challenge screen (enrolled accounts only) now explains that an authenticator already exists and how to get a reset (owner, admin or RideFlow support). In Arabic and English.
3. Production resets are unchanged: Members → Reset authenticator, Platform → operator administrators → Reset authenticator.

**Verification (actually run).**

- **Backend tests:** new tests check that an unconfirmed device still requires enrolment, and that the reset command refuses without DEBUG, refuses without the flag, deletes and audits, after which the next first factor reports `mfa_enrolled = false`.
  - Focused: `test_mfa_and_portal_api.py` and `test_auth.py`, 25 passed.
  - Full suite: **115 passed**. ruff clean.
- **Frontend:** `tsc` 0 errors; `eslint` 0 findings; admin image rebuilt.
- **Browser, operator `+967700000001`:**
  1. Ran the dev reset.
  2. OTP led to the setup screen: QR plus manual key, no 6-digit field before setup.
  3. A wrong TOTP was rejected and the user stayed on `/login`; nothing was activated.
  4. A correct TOTP led to `/operator`.
  5. After sign-out and sign-in again, OTP led to the 6-digit challenge only (no QR, no key, guidance shown).
  6. The next TOTP led to `/operator`.
- **Browser, platform `+967700000000`:** the same sequence (password, setup with QR, TOTP, `/platform`; then sign-out, challenge only, TOTP, `/platform`).
- **Final state:** both demo authenticators were reset again so the owner can enrol their own device; `MFADevice` count is 0.

**Fix commit:** `8faa72d163ec5cc69cbf89d3d7c3d26247d19589`
