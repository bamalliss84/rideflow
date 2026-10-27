import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rideflow_driver/app/providers.dart';
import 'package:rideflow_driver/core/api/api_client.dart';
import 'package:rideflow_driver/core/auth/session_store.dart';
import 'package:rideflow_driver/features/trip/trip_screen.dart';

import 'support/fake_backend.dart';

Map<String, dynamic> ride(String status, int version, List<String> actions) => {
      'id': 'r1',
      'status': status,
      'version': version,
      'viewer_role': 'driver',
      'allowed_actions': actions,
      'pickup_landmark': 'قرب الجامع',
      'dropoff_landmark': 'السوق',
      'currency': 'YER',
      'agreed_fare_minor': 150000,
      'estimate': {'distance_m': 3200},
      'rider': {'display_name': 'راكب', 'phone': null, 'trust': {}},
      'timestamps': {},
    };

void main() {
  testWidgets('renders only backend-allowed actions; a double tap sends ONE confirm with expected_version', (tester) async {
    var current = ride('match_pending', 3, ['confirm', 'decline']);
    final backend = FakeBackend({
      'GET rides/r1': (_) => (200, current),
      'POST rides/r1/confirm': (_) {
        current = ride('assigned', 4, ['driver_cancel', 'en_route', 'arrive']);
        return (200, current);
      },
      'GET rides': (_) => (200, {'results': []}),
      'GET driver/ride-offers': (_) => (200, []),
    });
    final store = SessionStore(MemoryKV());
    await store.save(const Tokens('a', 'r'));
    await tester.pumpWidget(ProviderScope(
      overrides: [
        sessionStoreProvider.overrideWithValue(store),
        apiClientProvider.overrideWith((ref) => ApiClient(session: store, dio: backend.dio(), appClientId: 'test-driver')),
      ],
      child: const MaterialApp(
        locale: Locale('ar'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: [AppLocalizations.delegate, GlobalMaterialLocalizations.delegate, GlobalWidgetsLocalizations.delegate, GlobalCupertinoLocalizations.delegate],
        home: TripScreen(rideId: 'r1'),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('action_confirm')), findsOneWidget);
    expect(find.byKey(const Key('action_decline')), findsOneWidget);
    expect(find.byKey(const Key('action_start')), findsNothing);
    expect(find.byKey(const Key('action_complete')), findsNothing);

    await tester.tap(find.byKey(const Key('action_confirm')));
    await tester.tap(find.byKey(const Key('action_confirm')), warnIfMissed: false);
    await tester.pumpAndSettle();

    final confirms = backend.seen.where((s) => s.path == 'rides/r1/confirm').toList();
    expect(confirms, hasLength(1));
    expect((confirms.single.body as Map)['expected_version'], 3);
    expect(confirms.single.headers['Idempotency-Key'], isNotEmpty);

    // After the refresh the next allowed actions come from the server.
    expect(find.byKey(const Key('action_en_route')), findsOneWidget);
    expect(find.byKey(const Key('action_arrive')), findsOneWidget);
    expect(find.byKey(const Key('action_driver_cancel')), findsOneWidget);
    expect(find.byKey(const Key('action_confirm')), findsNothing);
  });
}
