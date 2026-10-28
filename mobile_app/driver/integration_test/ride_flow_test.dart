// Full driver journey on the emulator against the local stack, with screenshots for review.
// Rider side: run `node scripts/rider_flow.mjs` (repository root) in parallel: it requests a ride at the
// emulator's GPS position, waits for this driver's bid, selects it and follows the trip.
//   flutter drive --driver=test_driver/integration_test.dart --target=integration_test/ride_flow_test.dart \
//     -d emulator-5554 --dart-define=APP_CLIENT_ID=demo-mukalla-driver --dart-define=DRIVER_PHONE=+967700000001
// On a host without a GPS (Windows desktop build), pass --dart-define=FIXED_LOCATION=14.5426,49.1242 and
// API_BASE_URL=http://127.0.0.1:8010: only the position source is fixed; API, WebSocket and rider are real.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show OffsetLayer;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:rideflow_driver/app/app.dart';
import 'package:rideflow_driver/app/providers.dart';
import 'package:rideflow_driver/core/auth/session_store.dart';
import 'package:rideflow_driver/core/location/location_service.dart';

const driverPhone = String.fromEnvironment('DRIVER_PHONE');
const fixedLocation = String.fromEnvironment('FIXED_LOCATION');

/// Desktop-host session store for this harness only: reusing the session across runs keeps re-runs within the
/// server's OTP rate limit (5 requests/hour per phone) instead of signing in every time.
class FileKV implements SecureKV {
  FileKV(this.path);
  final String path;
  Map<String, dynamic> _all() {
    final f = File(path);
    return f.existsSync() ? (jsonDecode(f.readAsStringSync()) as Map).cast<String, dynamic>() : <String, dynamic>{};
  }
  @override
  Future<String?> read(String key) async => _all()[key] as String?;
  @override
  Future<void> write(String key, String value) async => File(path).writeAsStringSync(jsonEncode({..._all(), key: value}));
  @override
  Future<void> delete(String key) async => File(path).writeAsStringSync(jsonEncode(_all()..remove(key)));
}

/// Position source for hosts without a GPS. Same contract as the real service (heartbeat re-sends the fix).
class FixedLocationService extends LocationService {
  FixedLocationService(String latLng)
      : lat = double.parse(latLng.split(',')[0]),
        lng = double.parse(latLng.split(',')[1]);
  final double lat, lng;
  Timer? _timer;
  Fix get _fix => Fix(lat: lat, lng: lng, accuracy: 8, deviceTs: DateTime.now());
  @override
  Future<LocationAccess> access({bool request = true}) async => LocationAccess.granted;
  @override
  Future<Fix?> current() async => last = _fix;
  @override
  void start({required Future<void> Function(Fix fix) onFix, required void Function(Object error) onError, Duration minInterval = const Duration(seconds: 10), Duration heartbeat = const Duration(seconds: 30)}) {
    stop();
    Future<void> send() async {
      try {
        await onFix(last = _fix);
      } catch (e) {
        onError(e);
      }
    }
    unawaited(send());
    _timer = Timer.periodic(heartbeat, (_) => send());
  }
  @override
  void stop() {
    _timer?.cancel();
    _timer = null;
  }
  @override
  bool get running => _timer != null;
}

/// Called with the step name when a wait times out, to capture what the screen showed.
Future<void> Function(String name)? onTimeout;

/// Scrolls the target into view first: desktop windows are short, and a tap off-screen silently misses.
Future<void> tapOn(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder.first);
  await tester.pump(const Duration(milliseconds: 200));
  await tester.tap(finder.first);
}

Future<void> waitFor(WidgetTester tester, Finder finder, {Duration timeout = const Duration(seconds: 60), void Function()? tick}) async {
  final end = DateTime.now().add(timeout);
  var n = 0;
  while (finder.evaluate().isEmpty) {
    if (DateTime.now().isAfter(end)) {
      await onTimeout?.call('zz-timeout');
      throw TestFailure('Timed out waiting for $finder');
    }
    if (n++ % 10 == 0) tick?.call(); // a refresh every ~5 s; faster would cancel each request before it lands
    await tester.pump(const Duration(milliseconds: 500));
  }
}

/// Desktop runs write PNGs straight to SCREENSHOT_DIR (the driver-side screenshot channel is mobile-only).
const screenshotDir = String.fromEnvironment('SCREENSHOT_DIR');

/// The online home screen animates continuously (live indicator), so pumpAndSettle would never return.
Future<void> pumpFor(WidgetTester tester, [Duration d = const Duration(milliseconds: 600)]) async {
  final end = DateTime.now().add(d);
  while (DateTime.now().isBefore(end)) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  final mobile = Platform.isAndroid || Platform.isIOS;

  Future<void> shot(WidgetTester tester, String name) async {
    if (mobile) {
      await binding.takeScreenshot(name);
      return;
    }
    if (screenshotDir.isEmpty) return;
    await tester.runAsync(() async {
      final view = tester.binding.renderViews.first;
      // The root layer is already in physical pixels (it carries the device-pixel-ratio transform).
      final image = await (view.debugLayer! as OffsetLayer).toImage(Offset.zero & tester.view.physicalSize);
      final png = await image.toByteData(format: ui.ImageByteFormat.png);
      await File('$screenshotDir/$name.png').writeAsBytes(png!.buffer.asUint8List());
    });
  }

  testWidgets('offer -> bid -> rider selects -> confirmation screen -> confirm -> trip -> complete -> cash', (tester) async {
    onTimeout = (name) => shot(tester, name);
    if (!mobile) {
      // Lay out as a phone (not the landscape desktop window) so screens and screenshots match the device.
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.75;
      addTearDown(tester.view.reset);
    }
    final container = ProviderContainer(overrides: [
      if (fixedLocation.isNotEmpty) locationServiceProvider.overrideWithValue(FixedLocationService(fixedLocation)),
      // Desktop host: the Windows credential store is not what ships; keep the session in memory there.
      if (!mobile) sessionStoreProvider.overrideWithValue(SessionStore(FileKV('${Directory.systemTemp.path}/rideflow_driver_e2e_session.json'))),
    ]);
    await tester.pumpWidget(UncontrolledProviderScope(container: container, child: const DriverApp()));
    if (mobile) await binding.convertFlutterSurfaceToImage();
    await pumpFor(tester, const Duration(seconds: 3));

    if (find.byKey(const Key('phone')).evaluate().isNotEmpty) {
      await shot(tester, '01-login');
      await tester.enterText(find.byKey(const Key('phone')), driverPhone);
      await tapOn(tester, find.byKey(const Key('sendCode')));
      await waitFor(tester, find.byKey(const Key('code')), timeout: const Duration(seconds: 20));
      await tester.enterText(find.byKey(const Key('code')), '000000');
      await tapOn(tester, find.byKey(const Key('verify')));
      await pumpFor(tester, const Duration(seconds: 5));
    }

    // Online and ready (server-confirmed fresh location). Wait for home to load (it may start signed in).
    await waitFor(tester, find.byKey(const Key('toggleOnline')), timeout: const Duration(seconds: 30));
    await pumpFor(tester, const Duration(seconds: 2));
    final ready = find.text('تصلك الطلبات القريبة الآن');
    if (ready.evaluate().isEmpty) {
      final notUpdating = find.byKey(const Key('locationNotUpdating'));
      if (notUpdating.evaluate().isEmpty) {
        await tapOn(tester, find.byKey(const Key('toggleOnline')));
        await pumpFor(tester, const Duration(seconds: 1));
        // First time: our explainer, then Android's own dialog (answered by the OS UI, not by a pm grant).
        if (find.byKey(const Key('allowLocation')).evaluate().isNotEmpty) {
          await shot(tester, '01b-location-explainer');
          await tapOn(tester, find.byKey(const Key('allowLocation')));
          await tester.pump(const Duration(seconds: 1));
        }
      }
    }
    await waitFor(tester, ready, tick: () => container.invalidate(eligibilityProvider));
    await pumpFor(tester, const Duration(seconds: 1));
    await shot(tester, '02-home-online');

    // An offer arrives (rider script) -> bid.
    final makeOffer = find.textContaining('قدّم عرضك');
    await waitFor(tester, makeOffer, timeout: const Duration(minutes: 3), tick: () => container.invalidate(offersProvider));
    await pumpFor(tester, const Duration(seconds: 1));
    await shot(tester, '03-offer');
    await tapOn(tester, makeOffer.first);
    await pumpFor(tester, const Duration(seconds: 1));
    await tester.enterText(find.byKey(const Key('bidAmount')), '700');
    await tapOn(tester, find.byKey(const Key('eta_5')));
    await pumpFor(tester);
    await shot(tester, '04-bid-sheet');
    await tapOn(tester, find.byKey(const Key('sendBid')));
    await pumpFor(tester, const Duration(seconds: 2));

    // Rider selects -> the confirmation screen opens by itself.
    await waitFor(tester, find.byKey(const Key('confirmTitle')), timeout: const Duration(minutes: 2));
    await tester.pump(const Duration(seconds: 1));
    await shot(tester, '05-confirmation');
    await tapOn(tester, find.byKey(const Key('confirmRide')));

    // Trip stages, driven only by server-allowed actions.
    for (final (action, name) in [('action_en_route', '06-assigned'), ('action_arrive', '07-en-route'), ('action_start', '08-arrived'), ('action_complete', '09-in-progress')]) {
      await waitFor(tester, find.byKey(Key(action)), timeout: const Duration(seconds: 40));
      await tester.pump(const Duration(milliseconds: 800));
      await shot(tester, name);
      await tapOn(tester, find.byKey(Key(action)));
      await tester.pump(const Duration(seconds: 2));
    }
    await waitFor(tester, find.byKey(const Key('confirmCash')), timeout: const Duration(seconds: 40));
    await shot(tester, '10-completed-cash');
    await tapOn(tester, find.byKey(const Key('confirmCash')));
    await waitFor(tester, find.text('أكّدت استلام النقد'), timeout: const Duration(seconds: 30));
    await shot(tester, '11-cash-confirmed');
  });
}
