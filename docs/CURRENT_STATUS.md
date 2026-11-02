# RideFlow current status

Checked on 2026-11-02 at about 09:40 Yemen time, from the repository, Git, the running containers, adb and the GitHub API. Update this file whenever the state changes. Decisions live in `project-management/06_DECISION_LOG.md`.

## Git

| | |
|---|---|
| Branch | `main`, level with `origin/main` |
| Last commit | `39b75a6` Driver app: one-step trip screen with call, maps, cancel reasons and rate later (D039) |
| Uncommitted | The D040 rider backend additions, across the backend, portal settings, driver app and docs (33 modified files, plus migrations, `push.py` and `tests/test_rider_additions.py`), and these two documentation files |
| Must stay out of commits | `rider_login.json` (dev token, untracked), `.env` (ignored) |

## Tests and CI

| Check | Result | Covers |
|---|---|---|
| CI run 41397706197 | Success: backend, admin, secret-scan | `39b75a6` only, not the uncommitted work. CI doesn't run Flutter |
| Backend `pytest` | 191 passed | Working tree, with D040 |
| `ruff check` and `ruff format --check` | Passed | Working tree |
| OpenAPI contract | Regenerated and matches the backend | Working tree |
| Portal `typecheck` and `lint` | Passed | Working tree |
| Driver `flutter analyze` | Clean | Working tree |
| Driver `flutter test` | 50 passed, 1 skipped (the live backend test) | Working tree |

Not run on the current work: `next build`, Playwright e2e (`apps/admin/e2e`), `integration_test/ride_flow_test.dart` (not run since trip model 1), `test/live`.

Seen only in tests, not on a screen: the driver's start code dialog, and the two new portal settings fields.

## Android on the real phone

- Device: Infinix X6840 (720x1576, 280 dpi), visible to adb over USB (`3226417000018213`) and wireless (`192.168.100.49:36339`; this port changes).
- `adb reverse tcp:8010 tcp:8010` is set on both connections.
- The owner confirmed the app connected with `API_BASE_URL=http://127.0.0.1:8010`, and approved the trip screen ("Looks good").
- Not confirmed: that a full trip ran on the phone, that the call and maps buttons work there, or GPS and camera permissions on the device.
- A debug APK with `url_launcher` built from a clean copy. In `mobile_app/driver`, one build failed with `PathExistsException` on a font file under `build/`; it looks like stale build output, and `flutter clean` is the expected cure. The D040 driver changes haven't been built for Android.
- The phone is outside Mukalla, so requests reach it only with a mock GPS app.

## Environment problem: LAN address, DisallowedHost and MFA

**What was observed**

- The API's allowed hosts are `localhost,127.0.0.1,api,10.0.2.2`, and the bypass is active (`dev_bypass_active()` returned True).
- Compose publishes the API on `127.0.0.1:8010` only, by design.
- Windows also has a port proxy, `192.168.100.48:8010 -> 127.0.0.1:8010` (`netsh interface portproxy show all`). It isn't in the repository, and it exposes the dev API to the LAN.
- The API logged 16 `DisallowedHost` errors for `192.168.100.48:8010` between 05:47 and 05:49 UTC on 2026-11-02, and none since.

**Cause**

1. A phone built with `API_BASE_URL=http://192.168.100.48:8010` reaches Django through the port proxy with that Host header.
2. That address isn't in `DJANGO_ALLOWED_HOSTS`, so Django answers 400. The app shows it as no connection.
3. Adding the address would stop that error but break the portal: `dev_bypass_active()` requires every allowed host to be local. The bypass turns off while the BFF's own flag stays on, so operators get asked for TOTP.

`ADMIN_MFA_REQUIRED=1` and `DEV_ADMIN_MFA_BYPASS=1` aren't themselves in conflict: "required, with a local exception" is D033's design. The conflict only appears once a LAN host is allowed. To test real MFA locally, set `DEV_ADMIN_MFA_BYPASS=0` deliberately and recreate `api` and `admin`.

**Safe fix (no code or security setting changes)**

1. Keep `DJANGO_ALLOWED_HOSTS` local.
2. Run the phone through `adb reverse` with `API_BASE_URL=http://127.0.0.1:8010`. This works over USB and wireless adb.
3. Recommended, for the owner to decide: remove the port proxy if nothing else needs it (run as administrator: `netsh interface portproxy delete v4tov4 listenaddress=192.168.100.48 listenport=8010`). It wasn't changed during this review.

A phone with no adb would need a real change, such as a separate LAN-only development setting that the bypass check ignores. That changes D033's rule, so it needs the owner's approval. Production isn't affected by any of this: its defaults are `RIDEFLOW_ENV=production` with the bypass off, and the API refuses to start with the flag set outside local development.

**Not confirmed**

- Who created the port proxy, or when.
- Why the `api` container started at 05:44 UTC, and whether that's when the `.env` hosts took effect. The owner reports the error appeared after recreating containers, which fits, but the logs can't prove it.
- Which address the phone's current build uses. The owner's note says the LAN address; the logs show no such request since 05:49 UTC, and the working run used `127.0.0.1`.

## Server and portal now

- `api`, `admin`, `db`, `redis` and `worker` are up; `/health/ready` returns 200 and the portal answers at port 3000.
- 500 errors on rides, offers, location and the dashboard between 06:24 and 06:26 UTC were caused by running the D040 code before its migration (`column rides_ride.cancel_reason_code does not exist`). They stopped after `migrate` at 06:30 UTC, and the local database is migrated. None appeared in the last few minutes checked.
- `worker` has been up for 5 days, so it still runs the code it started with. Restart it before relying on background timeouts with D040: `docker compose restart worker`. Not done, because this review changed nothing.
- Operator portal sign-in was last verified in the browser before D040. The bypass check passes today, but sign-in wasn't repeated.

## Documents that are out of date

Left unchanged in this review:
- `project-management/05_PROJECT_STATE.md` (dated 2026-10-22) and `00_START_HERE.md` (says planning).
- D035 says "not implemented yet"; it is implemented since D038. D036's rounding deferral is overridden by D038.
- `BUSINESS_RULES.md` section 2 still marks the rider price as pending review.
- `mobile_app/README.md` says the dev API isn't exposed to the LAN, which the port proxy contradicts on this machine.

## Next steps, in order

1. Owner chooses the rider home screen: canvas board `Rider-Home-Options` (model 1, dark, is the recommendation).
2. Commit and push the D040 work when asked, then read CI. Restart `worker`.
3. Continue rider designs screen by screen: destination and price, offers, active trip, end of trip.
4. Build `mobile_app/rider` after the designs are approved, including the share-link page and a map provider.
5. The owner supplies Mukalla's emergency numbers and SMS and Firebase accounts.
