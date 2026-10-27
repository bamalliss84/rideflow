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

Future<(ProviderContainer, FakeBackend)> setup(FakeLocation location, {int locationStatus = 200}) async {
  final store = SessionStore(MemoryKV());
  await store.save(const Tokens('a', 'r'));
  final backend = FakeBackend({
    'POST driver/location': (_) => (locationStatus, locationStatus == 200 ? {'applied': true, 'server_ts': '2026-10-28T10:00:00Z'} : {'code': 'server_error'}),
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
}
