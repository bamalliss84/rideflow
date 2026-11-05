import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:rideflow_driver/app/providers.dart';
import 'package:rideflow_driver/core/api/api_client.dart';
import 'package:rideflow_driver/core/auth/session_store.dart';
import 'package:rideflow_driver/core/external_apps.dart';
import 'package:rideflow_driver/core/location/arrival_fix_queue.dart';
import 'package:rideflow_driver/core/location/location_service.dart';
import 'package:rideflow_driver/design/components.dart';
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

class _SlowLocation extends LocationService {
  final answer = Completer<Fix?>();
  int reads = 0;
  @override
  Future<Fix?> now() {
    reads++;
    return answer.future;
  }
}

/// Answers each read from a list, then has nothing.
class _Reads extends LocationService {
  _Reads(this.answers);
  final List<Fix?> answers;
  @override
  Future<Fix?> now() async => answers.isEmpty ? null : answers.removeAt(0);
}

class _OnlineSince extends OnlineController {
  _OnlineSince(this.ago);
  final Duration ago;
  @override
  OnlineState build() => OnlineState(online: true, lastSentAt: DateTime.now().subtract(ago));
}

class FakeApps extends ExternalApps {
  FakeApps({this.opens = true});
  final bool opens;
  final dialed = <String>[];
  final mapped = <(double, double)>[];
  @override
  Future<bool> dial(String phone) async {
    dialed.add(phone);
    return opens;
  }

  @override
  Future<bool> showOnMap(double lat, double lng) async {
    mapped.add((lat, lng));
    return opens;
  }
}

Future<FakeBackend> pumpApp(WidgetTester tester, Map<String, Handler> routes, String initial, {ExternalApps apps = const ExternalApps(), LocationService? location, SecureKV? prefs, OnlineController Function()? online}) async {
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
      externalAppsProvider.overrideWithValue(apps),
      prefsProvider.overrideWithValue(prefs ?? MemoryKV()),
      if (online != null) onlineControllerProvider.overrideWith(online),
      if (location != null) locationServiceProvider.overrideWithValue(location),
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
    expect(find.byKey(const Key('action_arrive')), findsNothing); // one next step at a time, even when the backend allows skipping
    expect(find.byKey(const Key('action_start')), findsNothing);
    expect(find.byKey(const Key('action_complete')), findsNothing);
    expect(find.byKey(const Key('callRider')), findsOneWidget); // contact available once assigned
    await tester.tap(find.byKey(const Key('tripMenu')));
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.byKey(const Key('action_driver_cancel')), findsOneWidget);
    await tester.tapAt(const Offset(5, 500)); // closes the menu
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

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

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Future<void> tapKey(WidgetTester tester, String key) async {
    await tester.ensureVisible(find.byKey(Key(key)));
    await tester.pump();
    await tester.tap(find.byKey(Key(key)));
    await settle(tester);
  }

  Future<void> openCancel(WidgetTester tester) async {
    await tester.tap(find.byKey(const Key('tripMenu')));
    await settle(tester);
    await tester.tap(find.byKey(const Key('action_driver_cancel')));
    await settle(tester);
  }

  Iterable<Seen> attempts(FakeBackend b) => b.seen.where((s) => s.path == 'rides/r1/contact-attempts');

  Map<String, dynamic> waiting({required Duration waited, int calls = 0, bool inside = true}) => {
        ...ride('arrived', 6, ['start', 'no_show', 'driver_cancel']),
        'timestamps': {'arrived_at': DateTime.now().subtract(waited).toUtc().toIso8601String()},
        'arrival': {'within_geofence': inside},
        'no_show': {'wait_seconds': 300, 'contact_required': true, 'contact_attempts': calls},
      };

  bool noShowEnabled(WidgetTester tester) {
    final button = tester.widget<RfButton>(find.byKey(const Key('action_no_show')));
    return button.onPressed != null;
  }

  testWidgets('no-show: locked with the time left during the wait', (tester) async {
    await pumpApp(tester, {'GET rides/r1': (_) => (200, waiting(waited: const Duration(minutes: 2), calls: 1))}, '/ride/r1');
    expect(noShowEnabled(tester), isFalse);
    expect(find.textContaining('يتاح «لم يحضر الراكب» بعد'), findsOneWidget);
  });

  testWidgets('no-show: after the wait it still asks for a call first', (tester) async {
    await pumpApp(tester, {'GET rides/r1': (_) => (200, waiting(waited: const Duration(minutes: 6)))}, '/ride/r1');
    expect(noShowEnabled(tester), isFalse);
    expect(find.text('اتصل بالراكب أولًا لتسجيل عدم حضوره.'), findsOneWidget);
  });

  testWidgets('no-show: explains an arrival recorded outside the pickup area', (tester) async {
    await pumpApp(tester, {'GET rides/r1': (_) => (200, waiting(waited: const Duration(minutes: 6), calls: 1, inside: false))}, '/ride/r1');
    expect(noShowEnabled(tester), isFalse);
    expect(find.textContaining('خارج نطاق نقطة الالتقاء'), findsOneWidget);
  });

  testWidgets('no-show: opens once wait and call are done, and reports with the ride version', (tester) async {
    final backend = await pumpApp(tester, {
      'GET rides/r1': (_) => (200, waiting(waited: const Duration(minutes: 6), calls: 1)),
      'POST rides/r1/no-show': (_) => (200, ride('no_show', 7, [])),
    }, '/ride/r1');
    expect(noShowEnabled(tester), isTrue);
    await tester.tap(find.byKey(const Key('action_no_show')));
    await settle(tester);
    expect((backend.seen.singleWhere((s) => s.path == 'rides/r1/no-show').body as Map)['expected_version'], 6);
  });

  testWidgets('stages: a cash-settled ride asks for the rating, a rated one shows its summary', (tester) async {
    await pumpApp(tester, {
      'GET rides/r1': (_) => (200, {
            ...ride('completed', 9, []),
            'cash': {'amount_minor': 70000, 'driver_confirmed_at': '2026-11-02T10:00:00Z'},
            'my_rating': {'stars': 5},
          }),
    }, '/ride/r1');
    expect(find.byKey(const Key('rated')), findsOneWidget);
    expect(find.byKey(const Key('rate_1')), findsNothing);
    expect(find.byKey(const Key('confirmCash')), findsNothing);
  });

  group('arrived button', () {
    Fix fixAged(int seconds) => Fix(lat: 14.5, lng: 49.1, accuracy: 7, deviceTs: DateTime.now().subtract(Duration(seconds: seconds)));

    test('a fix from the last 45 seconds is used without a new reading', () async {
      final fix = fixAged(30);
      expect(await (LocationService()..last = fix).now(), same(fix));
      expect(freshFix(fixAged(50), maxAge: const Duration(seconds: 45)), isNull);
    });

    testWidgets('sends the recent fix with its true time', (tester) async {
      Object? sent;
      final fix = fixAged(20);
      await pumpApp(tester, {
        'GET rides/r1': (_) => (200, ride('en_route', 5, ['arrive'])),
        'POST rides/r1/arrive': (r) {
          sent = r.body;
          return (200, ride('arrived', 6, ['start']));
        },
      }, '/ride/r1', location: LocationService()..last = fix);
      await tester.tap(find.byKey(const Key('action_arrive')));
      await settle(tester);
      final body = sent! as Map;
      expect(body['lat'], 14.5);
      expect(body['accuracy_m'], 7);
      expect(body['device_ts'], fix.deviceTs.toUtc().toIso8601String());
    });

    testWidgets('shows it is working while the location is read, and a second tap does nothing', (tester) async {
      final reading = _SlowLocation();
      var posts = 0;
      await pumpApp(tester, {
        'GET rides/r1': (_) => (200, ride('en_route', 5, ['arrive'])),
        'POST rides/r1/arrive': (_) {
          posts++;
          return (200, ride('arrived', 6, ['start']));
        },
      }, '/ride/r1', location: reading);
      await tester.tap(find.byKey(const Key('action_arrive')));
      await tester.pump();
      expect(find.descendant(of: find.byKey(const Key('action_arrive')), matching: find.byType(CircularProgressIndicator)), findsOneWidget);
      await tester.tap(find.byKey(const Key('action_arrive')), warnIfMissed: false);
      await tester.pump();
      expect(reading.reads, 1);
      expect(posts, 0);

      reading.answer.complete(fixAged(0));
      await settle(tester);
      expect(posts, 1);
    });
  });

  group('location stopped on the way to the rider', () {
    final enRoute = {'GET rides/r1': (_) => (200, ride('en_route', 5, ['arrive']))};

    testWidgets('warns that the arrival may have no location', (tester) async {
      await pumpApp(tester, enRoute, '/ride/r1', online: () => _OnlineSince(const Duration(minutes: 3)));
      await settle(tester);
      expect(find.byKey(const Key('tripLocationStopped')), findsOneWidget);
    });

    testWidgets('says nothing while it updates', (tester) async {
      await pumpApp(tester, enRoute, '/ride/r1', online: () => _OnlineSince(const Duration(seconds: 10)));
      await settle(tester);
      expect(find.byKey(const Key('tripLocationStopped')), findsNothing);
    });
  });

  group('arrived with no location', () {
    Fix fixNow() => Fix(lat: 14.5, lng: 49.1, accuracy: 7, deviceTs: DateTime.now());

    testWidgets('records the arrival at once and sends the location when it comes', (tester) async {
      Object? arrive;
      Object? late;
      var current = ride('en_route', 5, ['arrive']);
      final location = _Reads([null, null]);
      final prefs = MemoryKV();
      await pumpApp(tester, {
        'GET rides/r1': (_) => (200, current),
        'POST rides/r1/arrive': (r) {
          arrive = r.body;
          current = ride('arrived', 6, ['start']);
          return (200, current);
        },
        'POST rides/r1/arrival-location': (r) {
          late = r.body;
          return (200, {'recorded': true, 'counted': true});
        },
      }, '/ride/r1', location: location, prefs: prefs);
      await tester.tap(find.byKey(const Key('action_arrive')));
      await settle(tester);
      expect(arrive, {'expected_version': 5});
      expect(find.byKey(const Key('action_start')), findsOneWidget);
      expect(late, isNull, reason: 'there is still no location');
      expect(prefs.values[ArrivalFixQueue.storageKey], isNotNull);

      location.answers.add(fixNow());
      final scope = ProviderScope.containerOf(tester.element(find.byType(TripScreen)));
      unawaited(scope.read(arrivalFixQueueProvider).pump()); // awaiting it here would stall the test's fake clock
      await settle(tester);
      expect((late! as Map)['lat'], 14.5);
      expect(prefs.values[ArrivalFixQueue.storageKey], isNull);
    });

    testWidgets('a retried tap repeats the same request, so its key stays valid', (tester) async {
      final bodies = <Object?>[];
      var fail = true;
      await pumpApp(tester, {
        'GET rides/r1': (_) => (200, ride('en_route', 5, ['arrive'])),
        'POST rides/r1/arrive': (r) {
          bodies.add(r.body);
          if (fail) return (503, {'detail': 'down'});
          return (200, ride('arrived', 6, ['start']));
        },
      }, '/ride/r1', location: _Reads([fixNow(), Fix(lat: 15, lng: 50, accuracy: 7, deviceTs: DateTime.now())]));
      await tester.tap(find.byKey(const Key('action_arrive')));
      await settle(tester);
      fail = false;
      await tester.tap(find.byKey(const Key('action_arrive')));
      await settle(tester);
      expect(bodies, hasLength(2));
      expect(bodies[1], bodies[0]);
    });

    testWidgets('no-show says why it is not available', (tester) async {
      await pumpApp(tester, {
        'GET rides/r1': (_) => (200, {
              ...ride('arrived', 6, ['start', 'no_show']),
              'timestamps': {'arrived_at': DateTime.now().subtract(const Duration(minutes: 10)).toUtc().toIso8601String()},
              'arrival': {'distance_m': null, 'accuracy_m': null, 'within_geofence': null},
              'no_show': {'wait_seconds': 300, 'contact_attempts': 1, 'contact_required': true},
            }),
      }, '/ride/r1');
      await settle(tester);
      expect(find.textContaining('بدون موقع'), findsOneWidget);
      expect(tester.widget<RfButton>(find.byKey(const Key('action_no_show'))).onPressed, isNull);
    });
  });

  testWidgets('call before arrival: dials the rider and records nothing', (tester) async {
    final apps = FakeApps();
    final backend = await pumpApp(tester, {'GET rides/r1': (_) => (200, ride('en_route', 5, ['arrive']))}, '/ride/r1', apps: apps);
    await tapKey(tester, 'callRider');
    expect(apps.dialed, ['+967711000001']);
    expect(attempts(backend), isEmpty);
  });

  testWidgets('call after arrival: dials the rider and records a contact attempt', (tester) async {
    final apps = FakeApps();
    final backend = await pumpApp(tester, {
      'GET rides/r1': (_) => (200, ride('arrived', 6, ['start'])),
      'POST rides/r1/contact-attempts': (_) => (201, {}),
    }, '/ride/r1', apps: apps);
    await tapKey(tester, 'callRider');
    expect(apps.dialed, ['+967711000001']);
    expect((attempts(backend).single.body as Map)['method'], 'call');
  });

  testWidgets('call: nothing is recorded when the phone could not start the call', (tester) async {
    final backend = await pumpApp(tester, {'GET rides/r1': (_) => (200, ride('arrived', 6, ['start']))}, '/ride/r1', apps: FakeApps(opens: false));
    await tapKey(tester, 'callRider');
    expect(attempts(backend), isEmpty);
    expect(find.text('تعذّر فتح الاتصال على هذا الجوال.'), findsOneWidget);
  });

  Map<String, dynamic> located(String status) => {
        ...ride(status, 5, []),
        'pickup': {'lat': 14.5, 'lng': 49.1},
        'dropoff': {'lat': 14.6, 'lng': 49.2},
      };

  testWidgets('maps: opens the pickup before the trip', (tester) async {
    final apps = FakeApps();
    await pumpApp(tester, {'GET rides/r1': (_) => (200, located('en_route'))}, '/ride/r1', apps: apps);
    await tapKey(tester, 'openMap');
    expect(apps.mapped, [(14.5, 49.1)]);
  });

  testWidgets('maps: opens the destination during the trip', (tester) async {
    final apps = FakeApps();
    await pumpApp(tester, {'GET rides/r1': (_) => (200, located('in_progress'))}, '/ride/r1', apps: apps);
    await tapKey(tester, 'openMap');
    expect(apps.mapped, [(14.6, 49.2)]);
  });

  testWidgets('trip map: the arrival mark once the trip is over', (tester) async {
    await pumpApp(tester, {'GET rides/r1': (_) => (200, located('completed'))}, '/ride/r1');
    expect(find.byKey(const Key('tripMap')), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byKey(const Key('arrivedFlag')), findsOneWidget);
  });

  testWidgets('trip map: en_route', (tester) async {
    await pumpApp(tester, {'GET rides/r1': (_) => (200, located('en_route'))}, '/ride/r1');
    expect(find.byKey(const Key('tripMap')), findsOneWidget);
  });
  testWidgets('trip map: arrived', (tester) async {
    await pumpApp(tester, {'GET rides/r1': (_) => (200, located('arrived'))}, '/ride/r1');
    expect(find.byKey(const Key('tripMap')), findsNothing);
  });
  testWidgets('trip map: in_progress', (tester) async {
    await pumpApp(tester, {'GET rides/r1': (_) => (200, located('in_progress'))}, '/ride/r1');
    expect(find.byKey(const Key('tripMap')), findsOneWidget);
  });

  testWidgets('maps: hidden while waiting for the rider', (tester) async {
    await pumpApp(tester, {'GET rides/r1': (_) => (200, located('arrived'))}, '/ride/r1');
    expect(find.byKey(const Key('openMap')), findsNothing);
  });

  testWidgets('cancel: needs a reason, and sends the chosen one', (tester) async {
    var current = ride('en_route', 5, ['driver_cancel', 'arrive']);
    final backend = await pumpApp(tester, {
      'GET rides/r1': (_) => (200, current),
      'POST rides/r1/cancel': (_) {
        current = ride('cancelled_by_driver', 6, []);
        return (200, current);
      },
    }, '/ride/r1');
    Iterable<Seen> cancels() => backend.seen.where((s) => s.path == 'rides/r1/cancel');

    await openCancel(tester);
    await tester.tap(find.byKey(const Key('confirmCancel')));
    await settle(tester);
    expect(cancels(), isEmpty);

    await tester.tap(find.byKey(const Key('cancelReason_other')));
    await settle(tester);
    await tester.tap(find.byKey(const Key('confirmCancel')));
    await settle(tester);
    expect(cancels(), isEmpty); // "another reason" still needs words

    await tester.tap(find.byKey(const Key('cancelReason_wrong_pickup')));
    await settle(tester);
    await tester.tap(find.byKey(const Key('confirmCancel')));
    await settle(tester);
    final sent = cancels().single.body as Map;
    expect(sent['reason'], 'نقطة الالتقاء غير صحيحة');
    expect(sent['reason_code'], 'wrong_pickup');
  });

  group('start code', () {
    testWidgets('each trip stage shows the rider\'s description of that stop', (tester) async {
      await pumpApp(tester, {'GET rides/r1': (_) => (200, {...ride('arrived', 6, ['start']), 'pickup_note': 'عند البوابة', 'dropoff_note': 'خلف المستشفى'})}, '/ride/r1');
      expect(find.byKey(const Key('pickupNote')), findsOneWidget);
      expect(find.byKey(const Key('dropoffNote')), findsNothing);
    });

    Map<String, dynamic> waitingWithCode() => {...ride('arrived', 6, ['start']), 'start_code_required': true};

    testWidgets('a wrong code explains itself, and the right one starts with a new key', (tester) async {
      var current = waitingWithCode();
      final backend = await pumpApp(tester, {
        'GET rides/r1': (_) => (200, current),
        'POST rides/r1/start': (r) {
          if ((r.body as Map)['start_code'] != '4821') return (422, {'code': 'start_code_invalid', 'detail': 'refused'});
          current = ride('in_progress', 7, ['complete']);
          return (200, current);
        },
      }, '/ride/r1');
      Iterable<Seen> starts() => backend.seen.where((s) => s.path == 'rides/r1/start');

      await tapKey(tester, 'action_start');
      await tester.enterText(find.byKey(const Key('startCodeInput')), '1111');
      await tester.tap(find.byKey(const Key('confirmStartCode')));
      await settle(tester);
      expect(find.text('الرمز غير صحيح. تأكد منه مع الراكب.'), findsOneWidget);

      await tapKey(tester, 'action_start');
      await tester.enterText(find.byKey(const Key('startCodeInput')), '4821');
      await tester.tap(find.byKey(const Key('confirmStartCode')));
      await settle(tester);
      expect(starts(), hasLength(2));
      expect(starts().first.headers['Idempotency-Key'], isNot(starts().last.headers['Idempotency-Key']));
      expect(find.byKey(const Key('action_complete')), findsOneWidget);
    });

    testWidgets('an incomplete code is not sent', (tester) async {
      final backend = await pumpApp(tester, {'GET rides/r1': (_) => (200, waitingWithCode())}, '/ride/r1');
      await tapKey(tester, 'action_start');
      await tester.enterText(find.byKey(const Key('startCodeInput')), '12');
      await tester.tap(find.byKey(const Key('confirmStartCode')));
      await settle(tester);
      expect(backend.seen.where((s) => s.path == 'rides/r1/start'), isEmpty);
    });

    testWidgets('a ride without a code starts straight away', (tester) async {
      final backend = await pumpApp(tester, {
        'GET rides/r1': (_) => (200, ride('arrived', 6, ['start'])),
        'POST rides/r1/start': (_) => (200, ride('in_progress', 7, ['complete'])),
      }, '/ride/r1');
      await tapKey(tester, 'action_start');
      expect(find.byKey(const Key('startCodeInput')), findsNothing);
      expect((backend.seen.singleWhere((s) => s.path == 'rides/r1/start').body as Map).containsKey('start_code'), isFalse);
    });
  });

  testWidgets('cancel: another reason sends what the driver wrote, and going back sends nothing', (tester) async {
    final backend = await pumpApp(tester, {
      'GET rides/r1': (_) => (200, ride('en_route', 5, ['driver_cancel', 'arrive'])),
      'POST rides/r1/cancel': (_) => (200, ride('cancelled_by_driver', 6, [])),
    }, '/ride/r1');
    Iterable<Seen> cancels() => backend.seen.where((s) => s.path == 'rides/r1/cancel');

    await openCancel(tester);
    await tester.tap(find.text('رجوع'));
    await settle(tester);
    expect(cancels(), isEmpty);

    await openCancel(tester);
    await tester.tap(find.byKey(const Key('cancelReason_other')));
    await settle(tester);
    await tester.enterText(find.byKey(const Key('cancelReasonText')), 'ظرف طارئ');
    await settle(tester);
    await tester.tap(find.byKey(const Key('confirmCancel')));
    await settle(tester);
    expect((cancels().single.body as Map)['reason'], 'ظرف طارئ');
  });

  Map<String, dynamic> done(String? confirmedAt) => {
        ...ride('completed', 9, []),
        'cash': {'amount_minor': 70000, 'driver_confirmed_at': confirmedAt},
      };

  testWidgets('rate later: not offered before the cash is confirmed', (tester) async {
    await pumpApp(tester, {'GET rides/r1': (_) => (200, done(null))}, '/ride/r1');
    expect(find.byKey(const Key('confirmCash')), findsOneWidget);
    expect(find.byKey(const Key('rateLater')), findsNothing);
  });

  testWidgets('rate later: returns home once the cash is confirmed', (tester) async {
    await pumpApp(tester, {'GET rides/r1': (_) => (200, done('2026-11-02T10:00:00Z'))}, '/ride/r1');
    await tapKey(tester, 'rateLater');
    expect(find.text('HOME'), findsOneWidget);
  });
}
