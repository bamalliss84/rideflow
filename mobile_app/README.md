# RideFlow mobile apps

| Folder | Status |
|---|---|
| `driver/` | Flutter **driver** app (Android). Phase 4. |
| `rider/` | Reserved for the passenger app. Not started. |
| `shared/` | Reserved for shared Dart packages, created only when a second app genuinely needs shared code. |

The apps talk only to the RideFlow REST API (`/api/v1`, contract in `packages/contracts/openapi.yaml`) and the event WebSocket (`/ws/v1/events/`). The backend decides every permission, eligibility rule and ride-state transition; the app renders `allowed_actions` and never re-implements business rules.

## Development machine layout (this project)

| What | Where |
|---|---|
| Flutter SDK | `E:\development\flutter` (3.24.5, Dart 3.5.4, on PATH) |
| Android SDK | `C:\Users\HP\AppData\Local\Android\Sdk` (existing install; platforms 34/35, build-tools 35) |
| JDK | Android Studio's bundled JBR (found automatically by Flutter) |
| Emulator images | `D:\AndroidAVD\avd` (`ANDROID_AVD_HOME`; AVD `Medium_Phone_API_35`) |
| Pub cache | `D:\dev-cache\pub` (`PUB_CACHE`) |
| Gradle home / caches | `D:\dev-cache\gradle` (`GRADLE_USER_HOME`) |
| Temp files for builds | `D:\dev-cache\tmp` (`TEMP`/`TMP`) |
| Build outputs | `mobile_app/driver/build/` (on D:, git-ignored) |

Drive C: is nearly full, so caches and temp files go on D:. Load the variables for the current PowerShell session (no system settings are changed):

```powershell
. .\mobile_app\scripts\dev-env.ps1
```

## Run against the local backend

1. Start the stack from the repository root: `docker compose up -d`.
2. Pick the target:
   - **Android emulator:** use the default `API_BASE_URL=http://10.0.2.2:8010`. `10.0.2.2` is the emulator's alias for this PC's loopback. The dev API port stays bound to `127.0.0.1`, and `10.0.2.2` is in the dev `DJANGO_ALLOWED_HOSTS`.
   - **Physical device on Wi-Fi:** the dev API is intentionally not exposed to the LAN. Use `adb reverse tcp:8010 tcp:8010` and run with `--dart-define=API_BASE_URL=http://127.0.0.1:8010` (127.0.0.1 then means the PC through the USB tunnel).
3. Run the app from `mobile_app/driver` (or `.\scripts\run-emulator.ps1`):

```powershell
flutter run --dart-define=APP_CLIENT_ID=demo-mukalla-driver
```

- **Operator:** `APP_CLIENT_ID` selects the operator's registered driver application. Use `demo-mukalla-driver` for the demo tenant or `e2e-qa-driver` for the test tenant.
- **Sign-in:** use any phone number in international format (`+9677…`). The local OTP code is the development code (`000000`). A new number becomes a new driver in that operator.

## Tests

From `mobile_app/driver`:

```powershell
flutter analyze
flutter test                     # unit + widget tests (no backend needed)
$env:LIVE_API_URL="http://127.0.0.1:8010"; flutter test test/live   # full driver lifecycle against the running stack
```

The live test uses the dedicated `e2e-qa` tenant (`docker compose exec api python manage.py seed_e2e`). A reviewer approves the driver through the admin portal BFF (local dev MFA bypass). The test creates its own driver, rider and ride.

## Build

```powershell
flutter build apk --debug                      # local device testing (cleartext http allowed in debug only)
flutter build apk --release --dart-define=API_BASE_URL=https://api.example --dart-define=APP_CLIENT_ID=<operator-driver-app>
```

Release readiness is tracked in `docs/reports/PHASE_04_DRIVER_APP_REPORT.md`. Release signing, an https API and a push provider are still open.

## Strings

Arabic is the source language. Edit `driver/tool/gen_arb.py`, then run `python tool/gen_arb.py; flutter gen-l10n`.
