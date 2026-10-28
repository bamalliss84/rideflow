import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:rideflow_driver/app/providers.dart';
import 'package:rideflow_driver/core/api/api_client.dart';
import 'package:rideflow_driver/core/auth/session_store.dart';
import 'package:rideflow_driver/design/theme.dart';
import 'package:rideflow_driver/features/confirm/confirm_screen.dart';
import 'package:rideflow_driver/features/trip/trip_screen.dart';

import 'support/fake_backend.dart';

Map<String, dynamic> ride(String status, int version, List<String> actions, {DateTime? deadline}) => {
      'id': 'r1',
      'status': status,
      'version': version,
      'viewer_role': 'driver',
      'allowed_actions': actions,
      'pickup_landmark': 'قرب الجامع الكبير في حي الشرج',
      'dropoff_landmark': 'السوق المركزي',
      'currency': 'YER',
      'agreed_fare_minor': 70000,
      'match_deadline': deadline?.toUtc().toIso8601String(),
      'estimate': {'distance_m': 3200},
      'my_bid': {'id': 'b1', 'amount_minor': 70000, 'eta_seconds': 300, 'status': 'selected'},
      'rider': {'display_name': 'راكب', 'phone': status == 'match_pending' ? null : '+967711000001', 'trust': {'rating_avg': 4.8}},
      'timestamps': {},
    };

Future<FakeBackend> pumpApp(WidgetTester tester, Map<String, Handler> routes, String initial) async {
  final backend = FakeBackend({
    'GET rides': (_) => (200, {'results': []}),
    'GET driver/ride-offers': (_) => (200, []),
    ...routes,
  });
  final store = SessionStore(MemoryKV());
  await store.save(const Tokens('a', 'r'));
  final router = GoRouter(initialLocation: initial, routes: [
    GoRoute(path: '/', builder: (_, __) => const Scaffold(body: Text('HOME'))),
    GoRoute(path: '/ride/:id', builder: (_, s) => TripScreen(rideId: s.pathParameters['id']!)),
    GoRoute(path: '/confirm/:id', builder: (_, s) => ConfirmRideScreen(rideId: s.pathParameters['id']!)),
  ]);
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 2.75;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(ProviderScope(
    overrides: [
      sessionStoreProvider.overrideWithValue(store),
      apiClientProvider.overrideWith((ref) => ApiClient(session: store, dio: backend.dio(), appClientId: 'test-driver')),
    ],
    child: MaterialApp.router(
      theme: buildRideFlowTheme(),
      locale: const Locale('ar'),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: const [AppLocalizations.delegate, GlobalMaterialLocalizations.delegate, GlobalWidgetsLocalizations.delegate, GlobalCupertinoLocalizations.delegate],
      routerConfig: router,
    ),
  ));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
  return backend;
}

void main() {
  testWidgets('confirmation screen: one confirm per double tap (expected_version + idempotency key), then the trip', (tester) async {
    var current = ride('match_pending', 3, ['confirm', 'decline'], deadline: DateTime.now().add(const Duration(seconds: 50)));
    final backend = await pumpApp(tester, {
      'GET rides/r1': (_) => (200, current),
      'POST rides/r1/confirm': (_) {
        current = ride('assigned', 4, ['driver_cancel', 'en_route', 'arrive']);
        return (200, current);
      },
    }, '/confirm/r1');

    expect(find.byKey(const Key('confirmTitle')), findsOneWidget);
    expect(find.text('اختارك الراكب!'), findsOneWidget);
    expect(find.text('قرب الجامع الكبير في حي الشرج'), findsOneWidget);
    expect(find.text('700 YER'), findsOneWidget); // agreed fare, minor units -> major
    expect(find.byKey(const Key('confirmRide')), findsOneWidget);

    await tester.tap(find.byKey(const Key('confirmRide')));
    await tester.tap(find.byKey(const Key('confirmRide')), warnIfMissed: false);
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }

    final confirms = backend.seen.where((s) => s.path == 'rides/r1/confirm').toList();
    expect(confirms, hasLength(1));
    expect((confirms.single.body as Map)['expected_version'], 3);
    expect(confirms.single.headers['Idempotency-Key'], isNotEmpty);
    // Landed on the trip screen with the next server-allowed actions.
    expect(find.byKey(const Key('rideStatus')), findsOneWidget);
    expect(find.byKey(const Key('action_en_route')), findsOneWidget);
    expect(find.byKey(const Key('action_confirm')), findsNothing);
  });

  testWidgets('confirmation screen: confirming after the deadline shows the explicit "time ran out" state', (tester) async {
    var current = ride('match_pending', 3, ['confirm', 'decline'], deadline: DateTime.now().add(const Duration(seconds: 50)));
    await pumpApp(tester, {
      'GET rides/r1': (_) => (200, current),
      'POST rides/r1/confirm': (_) {
        current = {...ride('bidding', 4, []), 'viewer_role': 'candidate'};
        return (409, {'code': 'invalid_transition', 'detail': "'confirm' is not allowed while the ride is bidding."});
      },
    }, '/confirm/r1');
    await tester.tap(find.byKey(const Key('confirmRide')));
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }
    expect(find.text('انتهت مهلة التأكيد'), findsOneWidget);
    expect(find.text('العودة للرئيسية'), findsOneWidget);
  });

  testWidgets('trip screen: only backend-allowed actions; a double tap sends ONE transition with expected_version', (tester) async {
    var current = ride('assigned', 4, ['driver_cancel', 'en_route', 'arrive']);
    final backend = await pumpApp(tester, {
      'GET rides/r1': (_) => (200, current),
      'POST rides/r1/en-route': (_) {
        current = ride('en_route', 5, ['driver_cancel', 'arrive']);
        return (200, current);
      },
    }, '/ride/r1');

    expect(find.byKey(const Key('action_en_route')), findsOneWidget);
    expect(find.byKey(const Key('action_arrive')), findsOneWidget);
    expect(find.byKey(const Key('action_driver_cancel'), skipOffstage: false), findsOneWidget);
    expect(find.byKey(const Key('action_start')), findsNothing);
    expect(find.byKey(const Key('action_complete')), findsNothing);
    expect(find.text('+967711000001'), findsOneWidget); // contact visible once assigned

    await tester.tap(find.byKey(const Key('action_en_route')));
    await tester.tap(find.byKey(const Key('action_en_route')), warnIfMissed: false);
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }
    final calls = backend.seen.where((s) => s.path == 'rides/r1/en-route').toList();
    expect(calls, hasLength(1));
    expect((calls.single.body as Map)['expected_version'], 4);
    expect(find.byKey(const Key('action_en_route')), findsNothing);
    expect(find.byKey(const Key('action_arrive')), findsOneWidget);
  });
}
