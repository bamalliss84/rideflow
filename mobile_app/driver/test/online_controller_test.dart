import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rideflow_driver/app/providers.dart';
import 'package:rideflow_driver/core/api/api_client.dart';
import 'package:rideflow_driver/core/auth/session_store.dart';
import 'package:rideflow_driver/core/location/location_service.dart';

import 'support/fake_backend.dart';

class FakeLocation extends LocationService {
  FakeLocation(this.fix, {this.grant = LocationAccess.granted});
  Fix? fix;
  final LocationAccess grant;
  Future<void> Function(Fix)? onFix;
  void Function(Object)? onError;

  @override
  Future<LocationAccess> access({bool request = true}) async => grant;
  @override
  Future<Fix?> current() async => fix;
  @override
  void start({required Future<void> Function(Fix) onFix, required void Function(Object) onError, Duration minInterval = Duration.zero, Duration heartbeat = Duration.zero}) {
    this.onFix = onFix;
    this.onError = onError;
  }

  @override
  bool get running => onFix != null;
}

Future<(ProviderContainer, FakeBackend)> setup(FakeLocation location, {int locationStatus = 200, bool applied = true}) async {
  final store = SessionStore(MemoryKV());
  await store.save(const Tokens('a', 'r'));
  final backend = FakeBackend({
    'POST driver/location': (_) => (locationStatus, locationStatus == 200 ? {'applied': applied, 'server_ts': '2026-10-28T10:00:00Z'} : {'code': 'server_error'}),
    'POST driver/availability': (r) => (200, {
          'eligible': true,
          'reasons': [],
          'is_online': (r.body as Map)['online'] == true,
          'presence': {'has_location': true, 'fresh': true, 'stale_after_seconds': 120},
        }),
    'GET driver/eligibility': (_) => (200, {'eligible': true, 'reasons': [], 'is_online': true, 'presence': {'fresh': true}}),
    'GET driver/ride-offers': (_) => (200, []),
  });
  final container = ProviderContainer(overrides: [
    sessionStoreProvider.overrideWithValue(store),
    apiClientProvider.overrideWith((ref) => ApiClient(session: store, dio: backend.dio(), appClientId: 'test-driver')),
    locationServiceProvider.overrideWithValue(location),
  ]);
  addTearDown(container.dispose);
  return (container, backend);
}

void main() {
  test('a position older than two minutes does not count as the current one', () {
    final now = DateTime(2026, 11, 4, 2, 0);
    Fix at(Duration age) => Fix(lat: 14.5, lng: 49.1, accuracy: 8, deviceTs: now.subtract(age));
    expect(freshFix(at(const Duration(seconds: 119)), now: now), isNotNull);
    expect(freshFix(at(const Duration(minutes: 2)), now: now), isNull);
    expect(freshFix(at(const Duration(minutes: 9)), now: now), isNull);
    expect(freshFix(null, now: now), isNull);
  });

  group('location stopped', () {
    final now = DateTime(2026, 11, 5, 12);
    OnlineState sent(int secondsAgo, {bool online = true}) => OnlineState(online: online, lastSentAt: now.subtract(Duration(seconds: secondsAgo)));

    test('a normal gap between samples is not a warning', () => expect(locationStopped(sent(50), null, now), isFalse));
    test('warns before the server drops the driver', () {
      expect(locationStopped(sent(76), null, now), isTrue);
      expect(locationStoppedAfter.inSeconds, lessThan(120));
    });
    test('never while offline', () => expect(locationStopped(sent(500, online: false), null, now), isFalse));
    test('nothing sent yet says nothing', () => expect(locationStopped(const OnlineState(online: true), null, now), isFalse));
  });

  final fix = Fix(lat: 14.54, lng: 49.12, accuracy: 6, deviceTs: DateTime.utc(2026, 10, 28, 10));

  test('no position -> stays offline and never calls availability (no "ready" without a location)', () async {
    final (c, backend) = await setup(FakeLocation(null));
    await c.read(onlineControllerProvider.notifier).goOnline();
    final s = c.read(onlineControllerProvider);
    expect(s.online, isFalse);
    expect(s.noFix, isTrue);
    expect(backend.seen.where((r) => r.path == 'driver/availability'), isEmpty);
  });

  test('permission denied -> offline with the access problem, nothing sent', () async {
    final (c, backend) = await setup(FakeLocation(fix, grant: LocationAccess.deniedForever));
    await c.read(onlineControllerProvider.notifier).goOnline();
    expect(c.read(onlineControllerProvider).locationAccess, LocationAccess.deniedForever);
    expect(backend.seen, isEmpty);
  });

  test('a fix is sent (coordinates, accuracy, device time) BEFORE going online; then the updater runs', () async {
    final location = FakeLocation(fix);
    final (c, backend) = await setup(location);
    await c.read(onlineControllerProvider.notifier).goOnline();
    expect(backend.seen.map((r) => r.path).take(2).toList(), ['driver/location', 'driver/availability']);
    final body = backend.seen.first.body as Map;
    expect([body['lat'], body['lng'], body['accuracy_m'], body['device_ts']], [14.54, 49.12, 6.0, '2026-10-28T10:00:00.000Z']);
    final s = c.read(onlineControllerProvider);
    expect(s.online, isTrue);
    expect(s.lastSentAt, isNotNull);
    expect(location.running, isTrue);
  });

  test('failed background sends are kept in state (shown to the driver), not swallowed', () async {
    final location = FakeLocation(fix);
    final (c, _) = await setup(location);
    await c.read(onlineControllerProvider.notifier).goOnline();
    final (c2, _) = await setup(FakeLocation(fix), locationStatus: 503);
    // drive the updater of a container whose API fails
    await c2.read(onlineControllerProvider.notifier).adopt(true);
    final failing = c2.read(locationServiceProvider) as FakeLocation;
    await expectLater(failing.onFix!(fix), throwsA(anything));
    expect(c2.read(onlineControllerProvider).locationError, isNotNull);
    // a later successful send clears it
    await location.onFix!(fix);
    expect(c.read(onlineControllerProvider).locationError, isNull);
  });

  test('restart while the server says online: resumes the updater without prompting', () async {
    final location = FakeLocation(fix);
    final (c, backend) = await setup(location);
    await c.read(onlineControllerProvider.notifier).adopt(true);
    expect(c.read(onlineControllerProvider).online, isTrue);
    expect(location.running, isTrue);
    expect(backend.seen, isEmpty); // nothing sent until the updater produces a fix
  });

  group('send my location now', () {
    test('shows that it is sending, then says it was sent', () async {
      final (c, _) = await setup(FakeLocation(fix));
      final controller = c.read(onlineControllerProvider.notifier);
      final seen = <bool>[];
      c.listen(onlineControllerProvider, (_, s) => seen.add(s.sending));
      expect(await controller.sendNow(), SendResult.sent);
      expect(seen.first, isTrue, reason: 'the button shows the send while it runs');
      expect(c.read(onlineControllerProvider).sending, isFalse);
      expect(c.read(onlineControllerProvider).lastSentAt, isNotNull);
    });

    test('a reading the server already had is reported, not shown as sent', () async {
      final (c, _) = await setup(FakeLocation(fix), applied: false);
      expect(await c.read(onlineControllerProvider.notifier).sendNow(), SendResult.sameReading);
      expect(c.read(onlineControllerProvider).lastSentAt, isNull);
    });

    test('no position is reported', () async {
      final (c, backend) = await setup(FakeLocation(null));
      expect(await c.read(onlineControllerProvider.notifier).sendNow(), SendResult.noFix);
      expect(c.read(onlineControllerProvider).sending, isFalse);
      expect(backend.seen.where((s) => s.path == 'driver/location'), isEmpty);
    });

    test('back on screen while online, the location is sent at once', () async {
      final location = FakeLocation(fix);
      final (c, backend) = await setup(location);
      await c.read(onlineControllerProvider.notifier).adopt(true);
      await c.read(onlineControllerProvider.notifier).recheckAccess();
      expect(backend.seen.where((s) => s.path == 'driver/location'), hasLength(1));
    });
  });
}
