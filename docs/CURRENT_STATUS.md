# RideFlow current status

The Git and test sections were last updated on 2026-11-12. The sections on the environment problem, the server and out-of-date documents were last checked on 2026-11-02. Update this file whenever the state changes. Decisions live in `project-management/06_DECISION_LOG.md`.

## Git

| | |
|---|---|
| Branch | `main`; pushed up to `68b3a80` (push notifications), CI passed on it and on `ba581bf` |
| Last commits | `ba581bf` D050/D051, socket grace, background location; `68b3a80` Firebase push |
| Uncommitted | D052 (subscriptions: reminders, grace, plan value, invitations) in the API, portal, contract and docs; the driver battery guide. All checks pass; held for the owner's go-ahead |
| Must stay out of commits | `rider_login.json` (dev token), `.env`, `.secrets/` (Firebase key), `mobile_app/*/android/app/google-services.json` (all ignored) |

## Tests and CI (2026-11-12)

| Check | Result | Covers |
|---|---|---|
| CI | Passed on `68b3a80`. CI doesn't run Flutter | Not run on D052 |
| Backend `pytest` | Passed, no failures | D052 included (`test_subscription_growth.py`, `test_push.py`) |
| `ruff check`, `ruff format --check`, `makemigrations --check` | Passed | D052 included |
| OpenAPI contract and portal types | Regenerated; contract matches | D052 included |
| Portal `typecheck` and `lint` | Passed; admin container rebuilt | D052 included |
| Driver `flutter analyze` and `flutter test` | Clean; 108 passed, 1 skipped | Push, background location, battery guide |
| Rider `flutter analyze` and `flutter test` | Clean; 56 passed, 1 skipped | Push |

Seen on the phone by the owner (2026-11-12): new arrival time choices from the portal; a test push in both apps. On the Infinix (XOS), its own freezer (`com.transsion.usf`) freezes the driver app seconds after the screen locks, even with the foreground location service and the Android battery exemption. While frozen, pushes wait until unlock and location stops. With the phone's "background power saving" turned off, a push posted 10 seconds after sending with the screen locked; location still arrives only now and then. The driver app now has a battery guide (account tab, a home banner, and opened once on first going online): the Android exemption, steps per phone maker, and locking the app in recent apps; the owner tried it on the phone (2026-11-12). Not yet seen: steady location with the screen off, "send my location now" feedback, a push from a real trip event, any D052 reminder.

Canvas (version 53): `Rider-Flow-A` (the rider's whole flow in direction A, day and night; home has two models) and `Driver-Subscription-A` (D052 screens, night and day; "My subscription" has two models). Both wait for the owner's choice; nothing of them is coded yet.


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

0. Owner compares layout models A, B and C on the phones (account settings, "ترتيب الشاشات"; D044) and keeps one. Then remove the other two and the switch. Smaller type and the one search screen are built (D043), and day and night colours (D042).
1. Owner checks the map-first destination screen (D041) on the phone. A full trip already ran there on 2026-11-04, with the demo driver played through the API. Before that, the phone test found and fixed: a stale pickup location, and requests that never widened past the first wave. A driver who comes online later now sees open requests (D048). Home screens, wait times and the trip map are built from the recommended models (D049). Design direction A is approved (D050); the rider flow board in that direction is next. Any country and server-side settings (D051): operator region fields, `app.*` settings, `GET app/config`, the version header and socket push, and both apps reading, caching and refreshing them are built, uncommitted, and not yet seen on the phone or in the portal. `mobile_app/rider` is built from the approved boards (`Rider-Flow-V3`, `Rider-Account-V2`, `Rider-Style-V2`), uncommitted. 20 widget tests and a live trip against the local stack pass; a debug APK built. Not run on a device. Cairo is added as four fixed weights made from Google Fonts' variable file, with its licence in `assets/fonts/OFL-Cairo.txt`. Waiting: map tile source.
2. Owner tries arrival without location and the stale location warning (D045) and the three edits (D046) on the phone. Push when asked, then read CI. Restart `worker`.
3. Decide the production map and search provider. Also decide the demo service area: Fuwah (`14.4864, 49.0410`) lies just outside its western edge, so a ride can't start there.
4. Build the share-link page.
5. The owner supplies Mukalla's emergency numbers and SMS and Firebase accounts.
