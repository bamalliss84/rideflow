# Before the commercial release

Every note for "later" goes here, the day it comes up, so nothing is forgotten. Review this whole file before the
first release for sale, and tick an item only when it is done and verified. Add new items at the end of their
section, with the date.

## Accounts, codes and messages

- [ ] A real SMS provider for sign-in codes in each country. `OTP_PROVIDER=dev` must be off (settings refuse it without DEBUG). (2026-11-12)
- [ ] Push notifications seen on real phones for every event in `apps/notifications/push.py`, app closed and in the background. Built 2026-11-12; production keeps the service account key in the host's secret store, never in the image. (2026-11-12)
- [ ] A white notification icon (monochrome drawable) for both apps; Android shows the launcher icon as a grey square in the status bar. (2026-11-12)
- [ ] Push texts reviewed by the owner, and sent in the person's own app language rather than the operator's default. (2026-11-12)
- [ ] Emergency number set for each operator (`safety.emergency_phone`); the button stays off while it is empty. Mukalla's numbers come from the owner. (2026-11-12)

## Maps and search

- [ ] A production map tile source and place search with a paid key behind a backend proxy. `tile.openstreetmap.org` and `photon.komoot.io` are for light development only. (2026-11-12)

## Production setup

- [ ] `RIDEFLOW_ENV=production`, `DJANGO_DEBUG=0`, staff MFA on, real secrets outside the repository, TLS everywhere. (2026-11-12)
- [ ] No development switches: `DEV_ADMIN_MFA_BYPASS` off in the API and the portal, no `seed_demo`, `seed_e2e` or `seed_ui_demo` data. (2026-11-12)
- [ ] Database backups, restore tested, error monitoring and uptime alerts. (2026-11-12)
- [ ] The deploy builds the portal image on every release: the portal is a built container, so a change never shows until it is rebuilt (seen 2026-11-12). (2026-11-12)
- [ ] WebSocket keepalive tuned for weak networks: the server drops a socket that misses its ping for 30 s (Daphne 20/30 s); check on real mobile networks. (2026-11-12)

## Apps

- [ ] Release signing for both Android apps, store listings, privacy labels. (2026-11-12)
- [ ] Flutter analyze and tests run in CI for both apps. (2026-11-12)
- [ ] Checked on several real phones: camera, location, permissions, background location while the screen is off, weak network. (2026-11-12)
- [ ] First launch with no network: the apps start on their built-in settings and switch to the operator's as soon as they are online (D051). (2026-11-12)
- [ ] Design direction A (D050) applied to every screen of both apps, including the driver screens never redesigned: onboarding, subscription, history, earnings, notifications. (2026-11-12)
- [ ] Full English interface reviewed screen by screen. (2026-11-12)
- [ ] Confirmation sound and vibration. (2026-11-12)
- [ ] The automated trip journey (`integration_test/ride_flow_test.dart`) run on a physical phone. (2026-11-12)
- [ ] One shared package for the code both apps copy (`core`, `design`, `shared`), so a fix lands once. (2026-11-12)
- [ ] Notification permission (Android 13+) is asked at sign-in through Firebase; check the first-run prompt on a fresh install of both apps. (2026-11-12)

## Operators and settings

- [ ] Every operator has its country, currency symbol, calling code and distance unit filled in (D051). (2026-11-12)
- [ ] The owner approves or replaces every PROVISIONAL and PROPOSED setting in `apps/tenancy/policy.py`; each is marked in the portal. (2026-11-12)

## Product gaps

- [ ] Share-link viewing page for a shared trip. (2026-11-12)
- [ ] Rating extras: retaliation detection, delayed updates, a required reason for low ratings, reminders. (2026-11-12)

## Legal

- [ ] Open decisions D013, D014 and D015 closed; proposals D009 to D011 approved or replaced. (2026-11-12)
- [ ] Terms of use and privacy policy for each country an operator runs in. (2026-11-12)
