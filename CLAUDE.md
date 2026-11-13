# RideFlow: guide for Claude Code sessions

Read this first, then `docs/CURRENT_STATUS.md` (where work stands) and `docs/project-management/06_DECISION_LOG.md` (approved decisions; it wins over this file).

## Working with the owner

- Reply in Arabic, concisely. The owner tests on a real phone and approves designs screen by screen.
- Designs come before code. Show several models on the canvas, wait for approval, then build. The owner's "don't start" means report and wait.
- Commit or push only when asked. Push to `main` only after checks pass, then report the CI result.
- New decisions get the next ID in the decision log (latest: D054). Never rewrite an approved decision or treat a proposal as approved.
- Don't invent test results. Say what wasn't run or seen.
- Don't defer work the owner asked for. Anything that truly must wait goes into `docs/RELEASE_CHECKLIST.md` the same day; review that file before any release for sale.
- Never log OTP codes or tokens beyond the existing dev-only behaviour. Never weaken TLS, authentication or test assertions to make checks pass.
- Don't delete test data, reset databases, or remove SDKs, caches, Docker volumes, emulator data or user files without approval.
- `.env` and `rider_login.json` (a dev token) must stay out of commits. Don't copy `.env` values into files.
- Firebase: each app needs `android/app/google-services.json` to build, and the API reads the service account key from `.secrets/firebase-admin.json` (mounted read-only). All three stay out of git. Never print the key's contents.

## What RideFlow is

A multi-tenant ride-hailing SaaS. A tenant is an independent transport operator that may run several cities; the first pilot is Mukalla, Yemen. Fares are paid in cash to the driver, and operators earn from driver subscriptions (D002, D026). Riders get an indicative range and competing driver offers (D004). Arabic RTL first, and designed for weak networks (D005).

Tenancy (D017, D021-D023, ADR-0001): one shared database with strict isolation. Users are global identities with per-tenant memberships. The tenant comes from trusted app context (`X-RideFlow-App` before sign-in, the token after). PostgreSQL row-level security and composite foreign keys are applied automatically after every `migrate` (`apps/core/db.py`). Requests start "locked" until a tenant is bound. New routes must pass `tests/test_tenant_isolation.py`, which fails on any unclassified route.

## Repository

| Path | What |
|---|---|
| `services/api` | Django 5.2, DRF, Channels, PostGIS, Redis. Apps in `apps/`: `core`, `tenancy`, `accounts`, `drivers`, `geo`, `rides`, `subscriptions`, `trust`, `notifications`, `backoffice` |
| `apps/admin` | Next.js operator and platform portal, behind a BFF with HttpOnly cookies (ADR-0005). `/login`, `/platform/login`, `/operator/*` |
| `mobile_app/driver` | Flutter 3.24.5 driver app, Riverpod and go_router. Screens in `lib/features/`, design system in `lib/design/` |
| `mobile_app/rider` | Flutter rider app, same stack. Copied the driver's `core`, `design` and `shared` foundations; there is no shared package yet. `test/live` runs a whole trip against the local stack |
| `packages/contracts/openapi.yaml` | API contract, generated from the backend |
| `scripts/` | `dev-up.ps1`, `test.ps1`, `export-openapi.ps1`, `rider_flow.mjs` (rider side of a test trip) |
| `docs/` | `BUSINESS_RULES.md`, `ARCHITECTURE.md`, `DATA_MODEL.md`, `ADR/`, `project-management/`, `reports/` |

Backend conventions:
- The ride is one row with an explicit state machine (`apps/rides/state_machine.py`).
- Mutations use a row lock, `expected_version` (409 on mismatch), an `Idempotency-Key` and an append-only event.
- WebSocket messages are hints only; clients re-read REST (ADR-0004).
- Operator-tunable values live in `apps/tenancy/policy.py`. App behaviour is the `app.*` group, and the operator's region (country, currency symbol, distance unit, calling code) is on `Tenant` (D051). The apps read both from `GET app/config`, keep a copy on the phone, and re-read it when a response's `X-RideFlow-Config` header or the socket's `config` message reports a new version. Don't hard-code timings, currency or units in the apps or the portal.
- A raised exception rolls back the idempotent request, so counters that must persist return an error response instead (see `start_trip`).

## Commands

Machine setup: Flutter is at `E:\development\flutter`. Keep caches on D: (`PUB_CACHE=D:\dev-cache\pub`, `TEMP` and `TMP` at `D:\dev-cache\tmp`, or run `.\mobile_app\scripts\dev-env.ps1`). `adb` isn't on PATH: `%LOCALAPPDATA%\Android\Sdk\platform-tools\adb.exe`. `gh` isn't installed; read CI through the GitHub REST API.

```bash
# Stack (API on 127.0.0.1:8010, portal on 127.0.0.1:3000)
powershell -ExecutionPolicy Bypass -File scripts\dev-up.ps1 -Build -Seed
docker compose up -d
docker compose exec -T api python manage.py migrate   # run right after adding a migration: the API mounts the code live

# Backend checks (the container user can't write ruff's cache, so pass --no-cache)
docker compose exec -T api python -m pytest -q
docker compose exec -T api ruff check --no-cache .
docker compose exec -T api ruff format --no-cache --check .
docker compose exec -T api python manage.py makemigrations --check

# API contract: redirect on the host side, and regenerate the portal types (CI compares both)
docker compose exec -T api python manage.py spectacular --validate --fail-on-warn > packages/contracts/openapi.yaml
cd apps/admin && npm run gen:api && npm run typecheck && npm run lint

# The portal container is a built image: after any portal change, rebuild it or the owner sees the old one
docker compose build admin && docker compose up -d admin

# Driver app, from mobile_app/driver. Strings: edit tool/gen_arb.py, never the .arb files
python tool/gen_arb.py && flutter gen-l10n
flutter analyze
flutter test
```

Demo data: `seed_demo` (idempotent, all fake, tenant `mukalla-pilot`), `seed_e2e` (tenant `e2e-qa`), `seed_ui_demo` (local only: 3 open requests for an online driver, expire in about 15 minutes). Operator sign-in: workspace `demo-mukalla-admin`, phone `+967700000001`, code from `OTP_DEV_CODE` in `.env`.

Patching on this machine: quotes in Bash heredocs have broken before, and files mix CRLF and LF. For multi-file edits, write a Python script in the scratchpad that keeps each file's line endings.

## Running on a real phone

The dev API listens on loopback by design. Use USB or wireless adb:

```bash
adb reverse tcp:8010 tcp:8010
flutter run -d <device> --dart-define=API_BASE_URL=http://127.0.0.1:8010
```

The rider app's map and search need two more defines for development: `MAP_TILE_URL=https://tile.openstreetmap.org/{z}/{x}/{y}.png` and `GEOCODER_URL=https://photon.komoot.io`. Both are public servers meant for light testing, not production.

The address is compiled in, so changing it needs a full `flutter run`, not `R`. A new plugin also needs a full run. `adb reverse` is lost when the connection changes. Don't add the PC's LAN IP to `DJANGO_ALLOWED_HOSTS`: see "Security" below.

## Testing a full trip

1. Driver: phone `+967700000001`, online, located inside Mukalla (`14.5426, 49.1242`; a physical phone elsewhere needs a mock GPS app, or requests won't reach it).
2. Rider side, in its own terminal: `node scripts\rider_flow.mjs`. It requests a ride, waits up to 5 minutes for an offer, selects it and follows the trip for about 6 minutes.
3. On the phone: send an offer, confirm, then Set off, Arrived, Start trip, Complete, Received fare, Rating.
4. Automated journey: `integration_test/ride_flow_test.dart`, with the rider script running. It's written for the emulator or a Windows build with `FIXED_LOCATION`; it hasn't been run on a physical phone.

The emulator AVD has an unknown lock credential and a hung snapshot boot; don't guess the PIN.

## Approved design

Canvas: https://claude.ai/artifact/5vXMvWdh6gw6TSQupomxfi (keep using this one; files live under `project/`).

- Direction A, "calm premium" (D050, D054), in both apps: near-black and white, the brand green only for live states, no card borders, one main button colour (`RfColors.pri`), money in the text colour and gold (`RfColors.star`) only for stars. Night `#0B0F0D` / surface `#161B18` / text `#F2F4F3`; day `#FFFFFF` / sunken `#F3F4F3` / text `#0B0F0D`; live green `#12B76A` by day, `#32D583` by night. Palettes in each app's `lib/design/tokens.dart`. The driver defaults to night, the rider to day. The old "Souq" palette is gone.
- Font: IBM Plex Sans Arabic, bundled in both apps (the rider can still pick Tajawal or Cairo). The owner asked for smaller type twice: body 13, titles 14-18, captions 12, buttons 44/50 high (D043).
- Connected-route icons: green ring for "from", gold pin for "to", dashed line between.
- Driver screens: requests with tap-to-reveal cards (`Requests-Final`), one offer sheet (`Offer-Options` option 1), status bar after sending (`After-Send` model 3), confirmation (`Confirm-Options` model 1), trip one step at a time (`Trip-Options` model 1, `Trip-Stages`).
- Rider app (D040): same family, one main fact and one main button per screen, more breathing room than the driver app, map as the base with one panel over it, and it must work without a map.
- Rider screens follow `Rider-Flow-A` (home model 2, D053), all built (D054). The rider has a day appearance, the default, and a night one, switched in account settings (D042). Colours are read while building, so a widget using them can't be `const`. Destination screen: `Rider-Destination-Options`, models 1 and 3 both built and switched in account settings until the owner picks one (D041).
- Layout (D044): three models built in both apps and switched in account settings until the owner keeps one. `RfLayout` in `lib/design/tokens.dart`; build screens from `RfGroup`, `RfRow`, `RfFacts`, `RfStops` and `RfFoot` in `lib/design/components.dart`.
- Not redesigned yet in the driver app: onboarding, subscription, history, earnings, notifications (they only inherit the colours and the card shape).

## Pricing, offers and confirmation

- Indicative range: (base + per km x straight-line distance) +/- range percent, per operator (D036), rounded by `fare.round_unit_minor` (D038). Minimum fare, road factor, per-minute and dynamic pricing are out for now.
- Rider price (D035): optional, no maximum, and not below `fare.rider_min_pct` of the range's start (default 100%). It isn't shown as guaranteed until a driver accepts. While waiting for offers the rider may raise it but never lower it, and open offers stay as they are (D040 amends D035).
- Driver sees the range, plus the rider's price clearly when there is one. A driver may send any price, unrestricted by the range or the rider's price.
- Rider selects one offer (D004). The selected driver must then confirm within `match.driver_confirm_timeout_seconds` (default 60); a decline or timeout returns the request to bidding without penalty (D027). No price is final before that confirmation.
- A driver may hold several open offers (`bids.max_open_per_driver`) but runs one trip at a time. Confirming withdraws the driver's other offers; declining keeps them (D037). A driver may hide a request from their own list, without penalty.
- Ratings appear before the offer and after confirmation; below `trust.min_sample` ratings, "new" replaces the number (D038).
- Cash only: no wallet, stored cards or platform custody.
- Late cancels: free before match and for `cancellation.free_after_match_seconds` after. No-show needs the wait, a valid arrival and a contact attempt (D010, proposed values). "Arrived" is recorded even with no location, and a location that follows in time can still count (D045).

## Security

- Staff need TOTP MFA (D030). `ADMIN_MFA_REQUIRED` defaults to on, and production defaults stay on.
- Local bypass (D033): `DEV_ADMIN_MFA_BYPASS` works only with `DJANGO_DEBUG=1`, `RIDEFLOW_ENV=local` and ALLOWED_HOSTS containing nothing but local names (`mfa.LOCAL_HOSTS`, `*.localhost`). The API refuses to start if the flag is set without DEBUG and `RIDEFLOW_ENV=local`. The BFF needs its own flag. Tokens carry `mfa_dev`, never `mfa`.
- `ADMIN_MFA_REQUIRED=1` together with the bypass is the intended local setup: it isn't a conflict. Adding a LAN IP to ALLOWED_HOSTS is what breaks it, because the bypass turns itself off while the BFF stays on. Details and the safe fix: `docs/CURRENT_STATUS.md`.
- `settings.py` refuses `OTP_PROVIDER=dev` without DEBUG, and `seed_ui_demo` refuses to run outside local development. Compose defaults are for development only; production uses `RIDEFLOW_ENV=production` and sets real secrets outside the repository.
- Share links are signed and show no phone numbers; only the rider sees the start code. Keep both true.

## Done and not done

Done:
- Backend for rides, offers, trust, subscriptions and the portal.
- Driver app through the trip screen (D035-D039).
- Rider backend additions (D040): live driver position, free-cancel deadline and reason codes, start code, trip sharing API, emergency alert, raising the price, saved and recent places, device tokens, rider account deletion.

Not done:
- Rider app: a full trip ran on the owner's phone. Stops come from a live map with search (D041), on development servers only. 
- Share-link viewing page.
- Push (Firebase project `rideflow-cf3f1`) is built in the API and both apps; it sends once the service account key is at `.secrets/firebase-admin.json`. A test push to each app appeared on the owner's phone (2026-11-12); real trip events not yet seen. SMS provider: dev only.
- Production map and search provider for the rider app (a paid key needs a backend proxy), and emergency numbers for Mukalla (the owner must supply them).
- Android verification of camera, GPS and permissions; Flutter in CI; release signing.
- Rating extras: retaliation detection, delayed updates, required low-rating reason, reminders.
- Confirmation sound and vibration. Currency shows `YER` and distance `km` in Arabic text.
- Legal gates: D013, D014 and D015 are open; D009-D011 are proposals.
