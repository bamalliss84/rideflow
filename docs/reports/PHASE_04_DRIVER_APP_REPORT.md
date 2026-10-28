# Phase 4 — Driver app: critical fixes, redesign and end-to-end QA

Date: 2026-10-28 · Scope: `mobile_app/driver` (Flutter 3.24.5), driver review workflow (API + portal),
operator live map.

## 1. Critical: the selected driver could not confirm the ride

**Symptom.** Ride `b71dbc03-…`: the rider selected Demo Owner's bid, the ride went to `match_pending`,
and the driver had no usable way to confirm before the match expired.

**Root cause.** The `ride.selected` hint *was* delivered (the API logs showed the app re-reading
notifications, the ride, offers and the ride list within a second). The app only used it to
invalidate caches. Nothing navigated, nothing counted down, and the only trace was a small "current
ride" card above an empty offer list. A missed event (reconnect, restart, app in the background) left
no way back to the prompt.

**Fix.**

| Concern | Implementation |
|---|---|
| Source of truth | `PendingMatchController`: the ride in `match_pending` where viewer = driver and `confirm` is allowed. Fed by the hint (immediate) and reconciled from the server on start, sign-in, resume, socket reconnect and every 15 s. It never depends on the WebSocket alone. |
| Unmistakable prompt | `ConfirmRideScreen` opens by itself (once per ride@version): countdown ring to `match_deadline`, agreed fare, pickup/destination, distance, ETA, rider name and rating (no phone before confirmation, per policy), large Confirm and secondary Decline. |
| Duplicates | Idempotency key per action@version plus `expected_version`; double taps send one request (widget test). |
| Expiry / release / other driver | A 409/404 re-reads the ride and shows "time ran out" or "no longer waiting for you", never a raw error. |
| Public offers | Unchanged server rule: the ride leaves `bidding`, so it disappears from offers; the selected driver reaches it through the pending match. |
| Bounce after confirm (found on the real backend) | After a successful confirm, the trip screen received the stale `match_pending` snapshot while the re-read was in flight and redirected back to the confirmation page, which then showed "no longer waiting". It now waits for the fresh read. `test/confirm_navigation_test.dart` adds realistic latency and fails without the fix. |
| Startup dead end (found on the real backend) | Unreadable secure storage (an invalidated Keystore key or an interrupted write) means "signed out" instead of an error screen with nothing to retry. |

**Acceptance — verified against the real local stack** (API, Postgres/PostGIS, Redis, Channels and a
real rider client), 3 consecutive green runs. The rider timeline from the last run:

```
ride_requested → bid_received (6.8 s) → selected: match_pending v3 (9.5 s)
→ assigned v4 (12.9 s) → en_route → arrived → in_progress → completed → rider cash confirm
server events: requested, wave_dispatched, dispatch:bidding, bid_created, select:match_pending,
               confirm:assigned, en_route, arrive, start, complete, cash_confirmed
```

Selection to confirmation took about 3.4 s, including a deliberate pause for the screenshot.

## 2. GPS and realtime (kept from the P0 fix, verified again)

- Permission is asked from the app after an in-app explanation. Denied, denied-forever and
  service-off each have a state and an action (app settings or location settings). Access is
  rechecked on resume. No ADB is needed.
- The driver is never shown "online" without a fresh, server-confirmed location: `presence.fresh`
  comes from eligibility, and the server still rejects going online with a stale location. The home
  screen shows "location updated N s ago", "not updating" and "no fix" states.
- Location updates every 10 s on movement, with a 30 s heartbeat. Errors surface, nothing is
  swallowed. Foreground only; no background tracking.
- WebSocket: the Redis socket timeout fix is untouched. Backoff, resume by cursor, dedupe by cursor,
  and reconciliation after every reconnect.

## 3. Design system and redesign

- `lib/design/tokens.dart`, `theme.dart`, `components.dart`: colour, spacing, radius, shadow and a
  Tajawal type scale. Components: buttons (6 kinds), cards, pills, sheets (keyboard-safe), route
  stops, money, countdown ring, stage stepper, skeletons, banners, toasts.
- **Tajawal** 400/500/700/800 is bundled (`assets/fonts`, OFL) and applied globally, with no runtime
  download.
- Screens:
  - **Home:** one availability action, readiness and freshness, realtime state, real today totals
    (no invented earnings), offer cards and the bid sheet.
  - **Confirmation:** full screen.
  - **Trip:** stage stepper; only `allowed_actions` are offered; primary actions in the bottom bar so
    toasts float above them.
  - **Cash and rating.**
  - **Onboarding:** four steps; per-type number and expiry; plate vs document number; photo preview;
    upload progress and errors; camera or gallery; draft-until-submit explained; rejection reasons
    with resubmission.
  - **Subscription:** active plan and days remaining first, then trial, plans, deposit accounts with
    copy, receipt by camera or gallery, pending and rejected receipts, renewal. Everything comes from
    tenant configuration; no prices are hardcoded.
  - **Sign-in.**
- Screenshots: `docs/reports/phase4-screens/02…11` (rendered at a 1080×2400 phone viewport).

## 4. Review workflow (draft until submit)

Operators could approve or reject documents of a driver who had not yet submitted. Now review
requires `under_review`, `approved` or `suspended`; otherwise it returns `409 application_not_submitted`.
Queues use `submitted=true`, and the portal hides review actions for drafts. Self-approval, roles and
MFA are unchanged.

## 5. Operator portal — live map

`components/map/MapView.tsx` is a provider-agnostic adapter. Any XYZ raster tile service is
configured through `MAP_TILE_URL` and `MAP_ATTRIBUTION` (`docker-compose` build args, `.env.example`).
The CSP `img-src` opens only to that tile origin, and only when it is configured. With no provider
configured, the page shows the schematic and says plainly that the street map isn't configured; it
does not fake a map. A provider key in the URL is public by nature, so only a referrer-restricted key
belongs there. The live page shows the online count from the API. No ride-creation button was added.

## 6. Tests

| Suite | Result |
|---|---|
| Backend pytest (incl. new draft-review test) | 151 passed |
| ruff check + format | clean |
| Flutter analyze | no issues |
| Flutter unit/widget | 25 passed |
| Flutter live backend (`LIVE_API_URL`, e2e-qa tenant) | 1 passed (onboarding → approval → trial → online → bid → confirm → trip → cash → rating → realtime) |
| New regression tests | pending match (4), confirm → trip without bounce (latency), unreadable storage, onboarding/subscription compile + analyze |
| Real-stack driver journey (`integration_test/ride_flow_test.dart` + `scripts/rider_flow.mjs`) | passed ×3 |
| Admin tsc + eslint | clean |
| Playwright E2E (admin rebuilt) | 26 passed (25 existing + live map) |

## 7. What was not device-tested (stated explicitly)

- **Android emulator:** the AVD stopped booting during this session. Cold boot reaches a lock screen
  that has a credential set; the quick-boot snapshot hangs. The journey therefore ran on a **Windows
  desktop build of the same app** against the same backend. Real API, WebSocket, rider and server
  state machine were all exercised; only the position source was a fixed Mukalla coordinate
  (`FIXED_LOCATION`). Not device-verified in this pass:
  - the Android permission dialogs;
  - the location explainer and its transition to the OS prompt;
  - camera capture;
  - real GPS streaming.

  The location flow was device-verified in the previous pass (P0). The test runs unchanged on the
  emulator once it is unlocked.
- **Map tiles:** no provider is configured locally, so only the "not configured" path was exercised.

## 8. Limitations / follow-ups

- The driver home stays map-free until a tile provider (and its terms) is chosen for mobile.
- Fare estimates display with the tenant's minor units (for example 735.12 YER); consider rounding
  estimates to whole units in a policy setting.
