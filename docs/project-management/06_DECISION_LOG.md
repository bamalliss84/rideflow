# DECISION LOG — APPROVED vs PROPOSED
D001 APPROVED by user: Pilot city Mukalla, Yemen.
D002 APPROVED by user: Ride cash paid to driver.
D003 APPROVED by user: Driver subscription deposited to owner account; operational verification needed. (Clarified by D017: deposit goes to the operating tenant's account; for the pilot tenant this is the owner.)
D004 APPROVED by user: Indicative fares plus competing driver bids; rider selects offer.
D005 APPROVED by user: Weak-network design.
D006 APPROVED by user: Bilateral ratings and enforcement to improve compliance.
D007 APPROVED by user: ChatGPT project lead/reviewer, Claude Code local executor, later server staging.
D008 PROPOSED: Flutter/Django/PostGIS/Redis architecture, subject to environment and design review.
D009 PROPOSED: 5,000 YER/month, 60-day founder trial; requires driver interviews and approval.
D010 PROPOSED: 5-minute wait and 200m geofence; requires field calibration and approval.
D011 PROPOSED: Trust weights, tier thresholds, renewal discount and credits; requires policy and anti-fraud review.
D012 OPEN: Whether driver must reconfirm after rider selection; settle UX/latency vs reliability.
D013 OPEN: Exact legal permits, insurance, business registration, operating boundaries.
D014 OPEN: Deposit account/wallet provider, settlement evidence, fraud handling.
D015 OPEN: Compensation point exchange rate, monthly cap, expiry, appeal time.
D016 PARTIALLY RESOLVED (see D018): Dev OS Windows; remaining open: CI and staging resources.
D017 APPROVED by owner 2026-10-21: Product name RideFlow; multi-tenant ride-hailing SaaS. Tenant = independent transportation operator, may operate across multiple cities. Mukalla is the first pilot city, not a product limit. Shared PostgreSQL database with tenant-scoped operational records; strict tenant isolation across authentication, authorization, APIs, queries and relationships. Driver subscriptions kept separate from future SaaS operator subscriptions. Tenant-specific currencies, pricing policies, cancellation rules and configuration. All prior approved business features preserved (D001–D007). Rationale: sellable product. Impact: tenant_id on all operational data, isolation tests mandatory, policy values become tenant config. Linked task: T00-B; ADR-0001.
D018 RECORDED 2026-10-21 (facts, not policy): local path D:\projects\rideflow; Git remote https://github.com/bamalliss84/rideflow.git; default branch main.
D019 RECORDED 2026-10-21 by owner: Task T00-B redefined as Architecture & Documentation Baseline; former T00-B (docker-compose/CI) becomes T00-C.
D020 APPROVED by owner 2026-10-21 (Phase 1 mission): Backend stack Django + DRF, PostgreSQL/PostGIS, Redis, Django Channels, Docker Compose. Resolves the backend part of D008/OD-04 (ADR-0002 → ACCEPTED). Rationale: owner approval and a verified Windows toolchain (Docker Engine/Compose, Python, Git all PASS). Impact: services/api implemented on this stack. Linked task: Phase 1.
D021 APPROVED by owner 2026-10-21: Shared-database multi-tenant SaaS with strict server-side tenant isolation (reaffirms D017/ADR-0001). Implemented as a fail-closed tenant ORM manager, PostgreSQL FORCE row-level security with a non-superuser app role, composite (tenant_id, id) foreign keys, tenant-namespaced Redis/WebSocket/file paths, and a generated isolation test over every route. Linked task: Phase 1.
D022 APPROVED by owner 2026-10-21: Global user identity with separate tenant memberships. Resolves OD-01 and replaces its proposed default ("separate tenant-scoped accounts"). Impact: the phone number is unique globally; access, roles, trust profile, violations and subscriptions are per tenant membership/tenant. Linked task: Phase 1 (accounts, tenancy).
D023 APPROVED by owner 2026-10-21: The tenant is selected from trusted application context, and future white-label apps are supported. Resolves OD-03. Implemented as registered TenantApplication client ids (`X-RideFlow-App`) for unauthenticated OTP calls; after login the tenant comes only from the JWT claim `tid`. Request-body tenant ids are ignored. A mismatching app header is rejected. Linked task: Phase 1.
D024 APPROVED by owner 2026-10-21: React/Next.js is the future tenant/platform administration dashboard. Django Admin is limited to internal technical administration (staff only, mounted at /django-admin/). Impact: all admin capabilities are exposed as versioned REST APIs (/api/v1/admin/*, /api/v1/platform/*) with an OpenAPI contract in packages/contracts/. Linked task: Phase 1; Next.js in a later phase.
D025 APPROVED by owner 2026-10-21: The Flutter rider and driver apps will be developed in later phases (not in Phase 1).
D026 APPROVED by owner 2026-10-21: Monetisation model of the pilot operator. Cash fares are paid directly to drivers. The operator earns from driver subscriptions paid by bank deposit, with the receipt approved manually. There is no mandatory trip commission. Reaffirms D002/D003; the platform holds no custody of fares.
D027 APPROVED by owner 2026-10-21 (Phase 1 mission lists "rider selection, driver confirmation"): The selected driver must confirm before assignment. Resolves D012. The confirmation timeout is a tenant policy (`match.driver_confirm_timeout_seconds`, provisional default 60 s). A decline or timeout returns the request to bidding without penalty.
D028 ENGINEERING (Claude, 2026-10-21, needs owner review, non-policy): (a) RideRequest, Match and Trip are unified into one `Ride` aggregate with an explicit state machine, so every transition is a single row-locked, version-checked update. (b) All business numbers are tenant policy parameters labelled APPROVED/PROPOSED/PROVISIONAL in `apps/tenancy/policy.py` and exposed via GET /api/v1/admin/config. (c) Several defaults that touch open decisions are off or safe: deposit dual approval off (configurable), no-show compensation disabled (D015 open), renewal discount disabled (D011 proposed). Verified incidents only auto-activate warning or commitment effects; restrictions need a human. (d) Only a development OTP adapter exists (no SMS provider approved). Linked report: docs/reports/PHASE_01_BACKEND_REPORT.md.
D029 APPROVED by owner 2026-10-22 (Phase 2 mission): Admin portal built with Next.js App Router, TypeScript strict, Tailwind CSS and accessible in-house components. It is packaged as the `admin` Docker service on http://localhost:3000. Sessions use a backend-for-frontend with HttpOnly SameSite=Strict cookies plus CSRF double-submit; no tokens are kept in browser storage. See ADR-0005.
D030 APPROVED by owner 2026-10-22 (Phase 2 mission "close the Phase 1 administrator MFA gap"): TOTP MFA is mandatory for every staff role and for platform admins (ADR-0005). Staff roles are granted only to sessions carrying `mfa: true`. Secrets are encrypted at rest and replayed codes are rejected. The development OTP adapter now refuses to start unless DJANGO_DEBUG=1.
D031 ENGINEERING (Claude, 2026-10-22): Minimal backend additions made only because the portal needed them, documented in docs/reports/PHASE_02_ADMIN_REPORT.md §4:
- MFA endpoints and the app-context endpoint;
- riders list/detail and ratings list;
- platform overview (aggregates only), platform audit, tenant-admin list and MFA reset;
- member MFA reset;
- human-readable name fields on admin serializers;
- live operational counters on the dashboard;
- staff notifications for new work items;
- a multi-role member filter.
No change to RLS, tenant resolution, ride state machine or business policies.
D032 ENGINEERING (Claude, 2026-10-22), UI conventions:
- Arabic-first (RTL) with English (LTR), switched by a cookie; numbers use Latin digits for operational clarity.
- Light theme only in Phase 2.
- Maps are schematic SVG previews (no external tile provider, so no third-party data sharing or keys). A real map provider is a later decision.
- Exports are client-side CSV of data already returned by the API.
D033 APPROVED by owner 2026-10-22: Local-development-only admin MFA bypass, `DEV_ADMIN_MFA_BYPASS` (default off).
- **Effective only when all of these hold:** `DJANGO_DEBUG=1`, `RIDEFLOW_ENV=local`, and only local `ALLOWED_HOSTS` (localhost, 127.0.0.1, ::1, api, *.localhost). The API refuses to start if the flag is set without DEBUG and RIDEFLOW_ENV=local.
- **First factor unchanged.** The first factor (operator OTP / platform password) is still required.
- **Separate token claim.** Tokens carry `mfa_dev` (never `mfa`), honoured only while the bypass is active. Turning the flag off makes existing dev sessions lose staff and platform rights on the next request.
- **BFF opt-in.** The BFF needs its own `DEV_ADMIN_MFA_BYPASS=1` before it accepts such a session.
- **Where it is enabled.** Only by the local `docker-compose.yml` defaults; production defaults are unchanged.
- **Audit.** Logins record `dev_mfa_bypass`.
D034 ENGINEERING (Claude, 2026-10-25, Phase 3; needs owner review, security-only, no business-policy change):

**Administrator MFA recovery codes.**
- 10 one-time codes per user, stored as keyed hashes.
- Generated only in a TOTP-verified session plus a fresh authenticator code; regeneration invalidates old codes.
- Redeemable only after the first factor, within the per-challenge attempt limit.

**Production refuses to start with a weak or placeholder `DJANGO_SECRET_KEY` or without `MFA_ENCRYPTION_KEY`.** HSTS defaults on and API docs default off outside DEBUG.

**Client IP for throttling** comes only from trusted proxy hops (`TRUSTED_PROXY_COUNT`, default 0). Platform login is limited per account as well as per IP.

**Redis outages return 503 with `Retry-After`.**

Linked: `docs/reports/PHASE_03_QA_REPORT.md`, `PHASE_03_DEFECT_REGISTER.md`.

D035 APPROVED by owner 2026-11-01: Optional rider price and the driver app's new design. Approved as design and policy direction; **not implemented yet**.

**Optional rider price (rule text from the owner, 2026-11-01; written for owner review before any code).**
1. The system always calculates the indicative range automatically.
2. The rider may enter a proposed price. It is optional.
3. A proposed price must not be below the start of the range, or below a percentage of that start set by each operator.
4. Until a driver accepts, the rider must not be shown the proposed price as guaranteed.
5. Without a proposed price, the driver sees the system's indicative range.
6. With a proposed price, the driver sees it clearly beside the system's indicative range.
7. A driver may offer their own price. No price becomes the final fare until the rider selects and the driver confirms (D027).

**Clarifications approved by the owner, 2026-11-01.**
- Minimum: a percentage of the start of the range, set by each operator, default 100%. The minimum shown to the rider is rounded to a whole currency unit.
- No maximum on the proposed price.
- The rider cannot change the proposed price after sending the request; to change it, the rider cancels and requests again.
- The driver's own price is not limited by the rider's price or by the range.

**Hide request (approved by the owner, 2026-11-01).** A driver may hide a request from their own list. It affects only that driver, carries no penalty, and is saved on the server so it survives an app restart or a new phone. It does not touch the rider or other drivers. After hiding, the driver can undo, and an empty list offers to show hidden requests again.

**Requests screen approved by the owner, 2026-11-01** (canvas artboard `Requests-Final`): tabs for all, rider price and my offers, with the additions above.

**Offer screen approved by the owner, 2026-11-01** (canvas artboard `Offer-Options`, option 1): one bottom sheet for accepting the rider's price or sending the driver's own price.

**Driver app design** (canvas artboard `Rider-Price`): the "Souq" concept in its dark palette, Tajawal, connected-route icons for from/to, and compact request cards that reveal their actions on tap.

Impact: API and rider app need a rider price field; driver app needs the new cards. The rule in `docs/BUSINESS_RULES.md` section 2 is updated. Linked task: none yet; code waits for the owner's review of this text.

D036 APPROVED by owner 2026-11-01: Keep the current fare estimate for now: (base + per km x straight-line distance) +/- range percent, set per operator.
- Rationale: pricing should not hold up the next step.
- Proposed by Claude and deferred, not approved: minimum fare, road factor and rounding unit. Per-minute pricing, map-based distance and dynamic pricing also stay out.
- Impact: no backend change. The values remain provisional and each operator must set them before launch. Estimates can still show decimals, such as 735.12.
- Linked task: none.

D037 APPROVED by owner 2026-11-01: One active trip per driver stays, and a confirmed trip closes the driver's other offers.
- A driver may hold several open offers but runs one trip at a time. A "next trip" feature, starting only after the current trip ends, is a later option and not approved for now.
- When a driver confirms a ride, their open offers on other rides are withdrawn automatically, and those riders are notified. Declining keeps them open. Implemented in `apps/rides/services.py` `confirm_match`.
- After sending an offer: the request moves to "My offers" and a fixed status bar shows the time left (canvas artboard `After-Send`, model 3). Sending errors stay in the offer sheet (artboard `Offer-Errors`). Retrying a send must reuse the same idempotency key.
- Rationale: an offer the driver can no longer honour wastes the rider's time.
- Impact: backend behaviour for the withdrawal; the driver app design is not implemented yet.
- Linked tests: `tests/test_concurrency.py`.

D038 APPROVED by owner 2026-11-01: Rating placement, confirmation screen and the start of implementation.
- Ratings show before the offer: request card and offer sheet for the driver, offers list for the rider, both sides after confirmation. Below `trust.min_sample` ratings, "new" replaces the number.
- Confirmation screen: canvas artboard `Confirm-Options`, model 1, with `Confirm-States`.
- Estimate rounding is approved and overrides the deferral in D036 (`fare.round_unit_minor`). `fare.bid_step_minor` sets the driver app's price step. Minimum fare and road factor stay deferred.
- Not implemented yet: retaliation detection, delayed rating updates, a required reason for low ratings, rating reminders.
- Linked tests: `tests/test_rider_price_and_hide.py`, `mobile_app/driver/test/requests_test.dart`.

D039 APPROVED by owner 2026-11-02: The driver's active trip screen is model 1, one step at a time (canvas artboards `Trip-Options`, `Trip-Stages`), with these extras.
- Stages: to the rider, waiting, to the destination, collect the fare, then rating as its own screen. One next action shows at a time, even where the backend allows skipping "en route". Cancel moves into a menu.
- During the wait, "Rider didn't show" stays locked and says why: time left, a call is needed, or the arrival was outside the pickup area. The backend still decides (`mark_no_show`), and the ride now returns `no_show` to the driver with the wait and call count.
- Call button opens the phone's dialer. After arrival, a call that opens also records the contact attempt, replacing the manual button. Before arrival nothing is recorded, because recording tells the rider the driver is waiting.
- "Open in maps" opens the phone's maps app: the pickup before the trip, the destination during it. There is no in-app map.
- Cancelling uses ready-made reasons, and "another reason" asks for text. The chosen text is stored as the cancel reason.
- "Later" on the rating leaves it available from My rides within `ratings.window_days`. It is offered once the driver has confirmed the cash.
- Rationale: fewer steps while driving, and contact evidence that needs no extra tap.
- Impact: driver app, with the new `url_launcher` dependency, plus the read-only `no_show` field on the ride.
- Linked tests: `mobile_app/driver/test/trip_screen_test.dart`, `services/api/tests/test_rides.py`.

D040 APPROVED by owner 2026-11-02: Rider app scope, safety features and the backend they need. Amends D035 on raising the price.
- Order: backend additions, then design models approved screen by screen, then the rider app. The app isn't built until its design is approved.
- Design: Souq family (Tajawal, route icons), one main fact and one main button per screen, more breathing room than the driver app, map as the base with one panel over it, works without a map. Dark first, with a light model shown for comparison.
- Rider home screen approved by the owner, 2026-11-02: canvas artboard `Rider-Home-Options`, model 1, dark: map on top, one panel with the destination button, saved places and recent destinations.
- Rider request screens approved by the owner, 2026-11-02: canvas artboard `Rider-Request-Options`: the destination step, then model 1: route map, estimate, and an optional price one tap away.
- Rider style approved by the owner, 2026-11-02: canvas artboard `Rider-Style-V2`, redrawn from the owner's reference image. It covers home, destination, request, offers and driver on the way, and replaces the look of the earlier rider boards while keeping their approved structure. Main buttons are green, prices and ratings gold; the driver app stays as approved. Offers: tap a card to select, one fixed button below, no card selected at first. The driver's initial shows when there is no photo; driver photos are not built. The map route is illustrative until a routing service exists.
- Rider trip screens approved by the owner, 2026-11-02: canvas artboard `Rider-Flow-V2`: setting or raising the price, waiting for offers, driver confirmation, driver arrived, on the trip, end of trip.
- Owner's 16-screen reference, 2026-11-02: the owner asked to adopt its features, data layout, font and sizes. Drawn on canvas artboard `Rider-Flow-V3`, approved by the owner 2026-11-02 together with `Rider-Account-V2`; it supersedes `Rider-Flow-V2` for layout. Adopted: from and to with swap, stats strips, offer sort tabs, a confirmation checklist, a confirmed screen, fuller-width pill buttons, a rating note, a receipt, current and past trip tabs. Left out because they conflict with approved rules or the backend: chat, scheduled rides, a separate booking confirmation, editing the price down, rider-pressed boarding and trip completion (the driver does these), remaining time and distance (no routing service). Font, decided by the owner 2026-11-02: the rider chooses Cairo or Tajawal in the account settings. The choice is kept on the device and both fonts ship with the app. Cairo, the closest match to the image (not an exact identification), is proposed as the default. The driver app stays on Tajawal. Prices stay gold.
- Live driver position goes to the rider of the matched ride only. Riders still see coarse positions before a match.
- Start code: optional, chosen by the rider per ride; `rides.start_code_required` lets an operator require it. Only the rider sees it. 5 wrong tries lock it for 5 minutes.
- Trip sharing: a signed link per ride, with no sign-in. It shows the destination, driver's first name, car and position, never a phone number, and nothing once the trip ends or the rider stops sharing. The viewing page isn't built yet.
- Emergency button: stays off until the operator sets `safety.emergency_phone`; the owner must supply approved numbers for Mukalla. Pressing it records evidence and alerts staff, and the phone makes the call.
- Raising the price: while waiting for offers the rider may only raise it. Open offers stay as they are.
- Cancellation: the ride says when free cancelling ends, and reasons have codes.
- Phone numbers stay visible to both sides at first; masking needs a calling provider that isn't confirmed for Yemen.
- Maps: MapLibre or similar with OpenStreetMap data. Real operation needs a suitable tile server. Not chosen in code yet.
- Account deletion: riders only, with a fresh OTP and no active ride. Finished rides stay for the operator's records under no name or phone. Drivers go through the operator.
- Providers not connected yet: Push (Firebase, adapter and device tokens exist, sends nothing) and SMS (the owner must choose a provider that works in Yemen).
- Not now: wallet and card payment, surge pricing, audio recording, in-app chat.
- Rationale: safety and a clear wait are what riders judge first; the rest follows comparison with Uber and inDrive.
- Impact: backend, API contract, portal settings, driver app (start code entry, cancel codes).
- Linked tests: `services/api/tests/test_rider_additions.py`, `services/api/tests/test_tenant_isolation.py`, `mobile_app/driver/test/trip_screen_test.dart`.

D041 APPROVED by owner 2026-11-04: The rider chooses stops on a live map, and both the point and the name come from the map. Amends D040's "a stop is a map point plus the rider's own words".
- Design: canvas artboard `Rider-Destination-Options`, model 1: full map with a fixed centre pin, a search pill on top, one panel below with the pickup, the live place name, the distance and the main button.
- Model 3 (a sheet under the map) was also built on the owner's request, 2026-11-04, so both can be compared on the phone. Account settings switch between them, and model 1 is the default until the owner picks one.
- Search and reverse lookup use OpenStreetMap data through the Photon API. Tested on Mukalla names: both `فوة` and `شعب البادية` were found with coordinates.
- A pin the rider hasn't moved can't be confirmed, and neither can a destination under 100 m from the pickup. Words typed by the rider remain only as the fallback when the map can't name a point.
- The start code moved to the price screen. Approved the same day: two optional descriptions there, one for where the rider is and one for the destination. They replace the single driver note in the rider app. The driver sees them only after the match, like the note, and old rides keep their note.
- Open: the production map and search provider. Public OpenStreetMap and Photon servers are for development only. A paid provider's key must not ship in the app, so that needs a backend proxy.
- Rationale: on the phone, a typed name such as `فوه` with an unmoved pin gave a wrong distance and price with no warning.
- Impact: rider app only.
- Linked tests: `mobile_app/rider/test/rider_screens_test.dart`.

D042 APPROVED by owner 2026-11-04: The rider app has a day and a night appearance, and the rider switches between them in the account settings. Amends the dark-only rider style in D040.
- Day is the default. Night keeps the approved `Rider-Style-V2` colours unchanged. The choice is saved on the phone.
- In night, map tiles are darkened; in day they show as they are.
- Day colours: ground `#F2F5F2`, cards `#FFFFFF`, text `#12211A`, muted `#4F6157`, line `#DDE3DD`, green `#0A7D46`, gold `#9A6700`, red `#B3261E`. The darker green, gold and red keep their contrast on white.
- Open: the layout. Canvas artboard `Rider-Day-Options` has two models for separating the data on each screen, and the owner hasn't picked one. This decision changes colours only.
- Rationale: the owner asked for a daytime app and for the choice between the two.
- Impact: rider app only. The driver app stays dark.
- Linked tests: `mobile_app/rider/test/rider_screens_test.dart`.

D043 APPROVED by owner 2026-11-04: Smaller type in both apps, and "where to" is one screen you type in. Amends D041's search pill and the earlier type sizes.
- Type: body 13, titles 14-18, captions 12, main buttons 50 high and others 44 (rider and driver). Large prices and codes shrink with them.
- Search: tapping "where to" opens the destination screen with the keyboard ready and the pickup shown. Results open over the map on that screen, and there is no separate search page. The same field stays on the map to search again.
- Open: how the data is laid out on each screen. That still follows the canvas models and the owner's choice.
- Rationale: on the phone, the owner found the type too large and the two search screens one too many.
- Impact: rider and driver apps.
- Linked tests: `mobile_app/rider/test/rider_screens_test.dart`.

Rule: New decisions get sequential ID, date, approver, rationale, impact and linked task. Never silently reinterpret proposals as approved.
