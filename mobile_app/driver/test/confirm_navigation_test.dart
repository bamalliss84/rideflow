import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rideflow_driver/app/app.dart';
import 'package:rideflow_driver/app/providers.dart';
import 'package:rideflow_driver/core/api/api_client.dart';
import 'package:rideflow_driver/core/auth/session_store.dart';
import 'package:rideflow_driver/core/realtime/events_socket.dart';

import 'support/fake_backend.dart';

class _NoSocket extends EventsSocket {
  _NoSocket(SessionStore s) : super(session: s);
  @override
  Future<void> start() async {}
}

Map<String, dynamic> ride(String status, int version, List<String> actions) => {
      'id': 'r1',
      'status': status,
      'version': version,
      'viewer_role': 'driver',
      'allowed_actions': actions,
      'pickup_landmark': 'قرب الجامع',
      'dropoff_landmark': 'السوق',
      'currency': 'YER',
      'agreed_fare_minor': 70000,
      'match_deadline': DateTime.now().add(const Duration(seconds: 55)).toUtc().toIso8601String(),
      'selected_at': DateTime.now().subtract(const Duration(seconds: 5)).toUtc().toIso8601String(),
      'my_bid': {'id': 'b1', 'amount_minor': 70000, 'eta_seconds': 300, 'status': 'selected'},
      'rider': {'display_name': 'راكب', 'trust': {'rating_avg': 4.8}},
      'timestamps': {},
    };

void main() {
  // Regression (real backend run): after a successful confirm the confirmation page stayed on top of the trip
  // showing "no longer waiting for you". The whole app router is used here, as on the device.
  testWidgets('app restores a pending match, confirm lands on the trip with no confirmation page left on top', (tester) async {
    final store = SessionStore(MemoryKV());
    await store.save(const Tokens('a', 'r'));
    var current = ride('match_pending', 3, ['confirm', 'decline']);
    final backend = FakeBackend({
      'GET me': (_) => (200, {
            'user': {'id': 'u', 'phone': '+967700000001', 'full_name': 'سائق'},
            'tenant': {'tenant_name': 'مشغل', 'roles': ['driver']},
            'currency': 'YER',
            'currency_minor_units': 2,
          }),
      'GET driver/eligibility': (_) => (200, {'eligible': true, 'reasons': [], 'subscription_active': true, 'status': 'approved', 'is_online': true}),
      'GET driver/ride-offers': (_) => (200, []),
      'GET rides': (_) => (200, {'results': current['status'] == 'match_pending' ? [current] : []}),
      'GET rides/r1': (_) => (200, current),
      'POST rides/r1/confirm': (_) {
        current = ride('assigned', 4, ['driver_cancel', 'en_route', 'arrive']);
        return (200, current);
      },
    }, latency: {'GET rides/r1': const Duration(milliseconds: 400)}); // the post-confirm re-read is in flight
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ProviderScope(overrides: [
      sessionStoreProvider.overrideWithValue(store),
      apiClientProvider.overrideWith((ref) => ApiClient(session: store, dio: backend.dio(), appClientId: 'test-driver')),
      eventsSocketProvider.overrideWith((ref) => _NoSocket(store)),
    ], child: const DriverApp()));
    for (var i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    expect(find.byKey(const Key('confirmRide')), findsOneWidget, reason: 'pending match restored on start');
    await tester.tap(find.byKey(const Key('confirmRide')));
    var bounced = false; // must hold in EVERY frame: a bounce is visible to the driver and steals taps
    for (var i = 0; i < 40; i++) {
      await tester.pump(const Duration(milliseconds: 100));
      bounced |= find.text('لم يعد الطلب بانتظارك').evaluate().isNotEmpty;
    }
    expect(bounced, isFalse, reason: 'trip must not redirect back to the confirmation page on the stale snapshot');

    expect(backend.seen.where((s) => s.path == 'rides/r1/confirm'), hasLength(1));
    expect(find.byKey(const Key('action_en_route')), findsOneWidget);
    expect(find.text('لم يعد الطلب بانتظارك'), findsNothing);
    expect(find.byKey(const Key('confirmRide'), skipOffstage: false), findsNothing);
  });
}
