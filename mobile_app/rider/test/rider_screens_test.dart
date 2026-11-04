import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:rideflow_rider/design/tokens.dart';
import 'package:rideflow_rider/app/app.dart';
import 'package:rideflow_rider/app/providers.dart';
import 'package:rideflow_rider/core/api/api_client.dart';
import 'package:rideflow_rider/core/auth/session_store.dart';
import 'package:rideflow_rider/core/external_apps.dart';
import 'package:rideflow_rider/data/models.dart';
import 'package:rideflow_rider/data/place_search.dart';
import 'package:rideflow_rider/design/components.dart';
import 'package:rideflow_rider/design/theme.dart';
import 'package:rideflow_rider/features/account/account_screen.dart';
import 'package:rideflow_rider/features/history/history_screen.dart';
import 'package:rideflow_rider/features/request/destination_screen.dart';
import 'package:rideflow_rider/shared/ride_map.dart';
import 'package:rideflow_rider/features/request/request_screen.dart';
import 'package:rideflow_rider/features/ride/ride_screen.dart';

import 'support/fake_backend.dart';

const _me = {
  'user': {'phone': '+967711000001', 'full_name': 'عبدالله'},
  'currency': 'YER',
  'currency_minor_units': 2,
};

Map<String, dynamic> ride(String status, {int version = 3, List<String> actions = const ['rider_cancel'], Map<String, dynamic> extra = const {}}) => {
      'id': 'r1',
      'status': status,
      'version': version,
      'allowed_actions': actions,
      'pickup': {'lat': 14.5, 'lng': 49.1},
      'dropoff': {'lat': 14.6, 'lng': 49.2},
      'pickup_landmark': 'قرب الجامع',
      'dropoff_landmark': 'السوق المركزي',
      'currency': 'YER',
      'estimate': {'min_minor': 72000, 'max_minor': 108000, 'distance_m': 2100, 'bid_step_minor': 5000},
      'timestamps': {},
      ...extra,
    };

Map<String, dynamic> driver({String? phone}) => {
      'display_name': 'سعيد',
      'phone': phone,
      'trust': {'rating_avg': 4.8, 'rating_provisional': false, 'completed_rides': 240},
      'vehicle': {'make': 'تويوتا', 'model': 'هايلكس', 'color': 'أبيض', 'plate_number': phone == null ? null : '12345'},
    };

Map<String, dynamic> offer(String id, int amount, {int eta = 300, Duration left = const Duration(seconds: 90)}) => {
      'id': id,
      'amount_minor': amount,
      'currency': 'YER',
      'eta_seconds': eta,
      'status': 'open',
      'expires_at': DateTime.now().add(left).toUtc().toIso8601String(),
      'created_at': DateTime.now().subtract(const Duration(seconds: 30)).toUtc().toIso8601String(),
      'driver': {...driver(), 'display_name': 'سائق-$id'},
    };

class FakeApps extends ExternalApps {
  final dialed = <String>[];
  @override
  Future<bool> dial(String phone) async {
    dialed.add(phone);
    return true;
  }
}

const _shaab = Point(14.5501, 49.1329);
const _fuwah = Point(14.4864, 49.0410);

class FakeSearch implements PlaceSearch {
  FakeSearch({this.reverseName = 'شعب البادية', this.fail = false});
  final String? reverseName;
  final bool fail;
  final queries = <String>[];
  final areas = <Point?>[];
  @override
  bool get available => true;
  @override
  Future<List<PlaceHit>> search(String query, {Point? near}) async {
    queries.add(query);
    areas.add(near);
    if (fail) throw Exception('offline');
    return query == 'فوة' ? const [PlaceHit(name: 'فوة', detail: 'المكلا', point: _fuwah)] : const [];
  }

  @override
  Future<PlaceHit?> reverse(Point point) async {
    if (fail) throw Exception('offline');
    return reverseName == null ? null : PlaceHit(name: reverseName!, detail: 'المكلا', point: point);
  }
}

Future<FakeBackend> pump(WidgetTester tester, Map<String, Handler> routes, String initial, {ExternalApps apps = const ExternalApps(), Object? extra, SecureKV? prefs, PlaceSearch? search, Point? here, bool overrideLocation = false}) async {
  final backend = FakeBackend({
    'GET me': (_) => (200, _me),
    'GET rides': (_) => (200, {'results': []}),
    'GET rides/r1/bids': (_) => (200, []),
    'GET rides/r1/driver-location': (_) => (404, {'code': 'driver_location_unavailable'}),
    ...routes,
  });
  final store = SessionStore(MemoryKV());
  await store.save(const Tokens('a', 'r'));
  final router = GoRouter(initialLocation: initial, initialExtra: extra, routes: [
    GoRoute(path: '/', builder: (_, __) => const Scaffold(body: Text('HOME'))),
    GoRoute(path: '/login', builder: (_, __) => const Scaffold(body: Text('LOGIN'))),
    GoRoute(path: '/ride/:id', builder: (_, s) => RideScreen(rideId: s.pathParameters['id']!)),
    GoRoute(path: '/receipt/:id', builder: (_, s) => ReceiptScreen(rideId: s.pathParameters['id']!)),
    GoRoute(path: '/destination', builder: (_, s) => DestinationScreen(initialDropoff: s.extra as Place?)),
    GoRoute(path: '/request', builder: (_, s) => RequestScreen(draft: s.extra! as RideDraft)),
    GoRoute(path: '/rides', builder: (_, __) => const Scaffold(body: HistoryScreen())),
    GoRoute(path: '/account', builder: (_, __) => const Scaffold(body: AccountScreen())),
  ]);
  tester.view.physicalSize = const Size(720, 1576);
  tester.view.devicePixelRatio = 1.75;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(ProviderScope(
    overrides: [
      sessionStoreProvider.overrideWithValue(store),
      prefsProvider.overrideWithValue(prefs ?? MemoryKV()),
      externalAppsProvider.overrideWithValue(apps),
      if (search != null) placeSearchProvider.overrideWithValue(search),
      if (overrideLocation) myLocationProvider.overrideWith((ref) async => here),
      apiClientProvider.overrideWith((ref) => ApiClient(session: store, dio: backend.dio(), appClientId: 'test-rider')),
    ],
    child: MaterialApp.router(
      theme: buildRideFlowTheme(),
      locale: const Locale('ar'),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: const [AppLocalizations.delegate, GlobalMaterialLocalizations.delegate, GlobalWidgetsLocalizations.delegate, GlobalCupertinoLocalizations.delegate],
      routerConfig: router,
    ),
  ));
  await settle(tester);
  return backend;
}

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

Iterable<Seen> posts(FakeBackend b, String path) => b.seen.where((s) => s.method == 'POST' && s.path == path);

void main() {
  group('requesting', () {
    const draft = RideDraft(pickup: Place('قرب الجامع', Point(14.5, 49.1)), dropoff: Place('السوق', Point(14.6, 49.2)), pickupNote: 'عند البوابة', dropoffNote: 'خلف المستشفى', requireCode: true);
    final estimate = {'distance_m': 2100, 'min_minor': 72000, 'max_minor': 108000, 'rider_price_min_minor': 72000, 'currency': 'YER'};

    testWidgets('a request without a price sends none, and double tapping creates one ride', (tester) async {
      final backend = await pump(tester, {
        'POST fare-estimate': (_) => (200, estimate),
        'POST rides': (_) => (201, ride('bidding')),
        'GET rides/r1': (_) => (200, ride('bidding')),
      }, '/request', extra: draft);
      await tester.tap(find.byKey(const Key('requestOffers')));
      await tester.tap(find.byKey(const Key('requestOffers')), warnIfMissed: false);
      await settle(tester);
      final body = posts(backend, 'rides').single.body as Map;
      expect(body.containsKey('rider_price_minor'), isFalse);
      expect(body['require_start_code'], isTrue);
      expect(body['pickup_note'], 'عند البوابة');
      expect(body['dropoff_note'], 'خلف المستشفى');
      expect(posts(backend, 'rides').single.headers['Idempotency-Key'], isNotEmpty);
      expect(find.byKey(const Key('searching')), findsOneWidget);
    });

    testWidgets('the price sheet starts at the minimum and cannot go below it', (tester) async {
      final backend = await pump(tester, {
        'POST fare-estimate': (_) => (200, estimate),
        'POST rides': (_) => (201, ride('bidding')),
        'GET rides/r1': (_) => (200, ride('bidding')),
      }, '/request', extra: draft);
      await tapKey(tester, 'addPrice');
      expect(tester.widget<IconButton>(find.byKey(const Key('priceDown'))).onPressed, isNull);
      await tester.tap(find.byKey(const Key('priceUp')));
      await settle(tester);
      await tester.tap(find.byKey(const Key('usePrice')));
      await tester.pump(const Duration(seconds: 1));
      await settle(tester);
      await tapKey(tester, 'requestOffers');
      expect((posts(backend, 'rides').single.body as Map)['rider_price_minor'], 77000);
    });

    testWidgets('a pickup outside the service area explains itself', (tester) async {
      await pump(tester, {'POST fare-estimate': (_) => (422, {'code': 'outside_service_area', 'detail': 'x'})}, '/request', extra: draft);
      expect(find.text('نقطة الانطلاق خارج نطاق الخدمة. اختر نقطة أخرى.'), findsOneWidget);
    });
  });

  group('choosing the destination on the map', () {
    final routes = <String, Handler>{
      'GET cities': (_) => (200, []),
      'GET me/places': (_) => (200, []),
      'GET me/recent-places': (_) => (200, []),
      'POST fare-estimate': (_) => (200, {'distance_m': 12170, 'min_minor': 72000, 'max_minor': 108000, 'rider_price_min_minor': 72000, 'currency': 'YER'}),
    };
    bool enabled(WidgetTester tester, String key) => tester.widget<RfButton>(find.byKey(Key(key))).onPressed != null;
    String text(WidgetTester tester, String key) => tester.widget<Text>(find.byKey(Key(key))).data!;

    testWidgets('a pin nobody moved cannot be confirmed; searching sets the name and the real point', (tester) async {
      final search = FakeSearch();
      final backend = await pump(tester, routes, '/destination', search: search, here: _shaab, overrideLocation: true);
      // Where to: the field is ready to type in, with the pickup above it and no second page.
      expect(find.byKey(const Key('searchInput')), findsOneWidget);
      expect(find.byKey(const Key('pin')), findsNothing);
      expect(text(tester, 'fromText'), 'موقعي الحالي، شعب البادية، المكلا');

      await tapKey(tester, 'backToMap');
      expect(find.byKey(const Key('pin')), findsOneWidget);
      expect(enabled(tester, 'showPrice'), isFalse);

      await tapKey(tester, 'searchInput');
      expect(find.byKey(const Key('pin')), findsNothing);
      await tester.enterText(find.byKey(const Key('searchInput')), 'فوة');
      await tester.pump(const Duration(milliseconds: 400));
      await settle(tester);
      expect(search.queries, ['فوة']);
      await tester.tap(find.byKey(const Key('hit_0')));
      await tester.pump(const Duration(seconds: 1));
      await settle(tester);

      expect(text(tester, 'placeTitle'), 'فوة، المكلا');
      expect(text(tester, 'placeHint'), contains('12.'));
      await tapKey(tester, 'showPrice');
      await tester.pump(const Duration(seconds: 1));
      await settle(tester);
      final body = backend.seen.firstWhere((s) => s.path == 'fare-estimate').body as Map;
      expect(body['pickup'], {'lat': _shaab.lat, 'lng': _shaab.lng});
      expect(body['dropoff'], {'lat': _fuwah.lat, 'lng': _fuwah.lng});
    });

    testWidgets('searching before the location is known stays in the operator\'s city', (tester) async {
      final search = FakeSearch();
      await pump(tester, {...routes, 'GET cities': (_) => (200, [{'name': 'المكلا', 'center': {'lat': 14.5426, 'lng': 49.1242}}])}, '/destination', search: search, overrideLocation: true);
      await tester.enterText(find.byKey(const Key('searchInput')), 'فوة');
      await tester.pump(const Duration(milliseconds: 400));
      await settle(tester);
      expect(search.areas.single?.lat, 14.5426);
      expect(search.areas.single?.lng, 49.1242);
    });

    testWidgets('a place chosen from the search shows close up', (tester) async {
      await pump(tester, routes, '/destination', search: FakeSearch(), here: _shaab, overrideLocation: true);
      double zoom() => tester.widget<RideMap>(find.byKey(const Key('destinationMap'))).controller!.camera.zoom;
      expect(zoom(), 15);
      await tester.enterText(find.byKey(const Key('searchInput')), 'فوة');
      await tester.pump(const Duration(milliseconds: 400));
      await settle(tester);
      await tester.tap(find.byKey(const Key('hit_0')));
      await tester.pump(const Duration(seconds: 1));
      await settle(tester);
      expect(zoom(), 18);
    });

    testWidgets('moving the map names the new point by itself', (tester) async {
      await pump(tester, routes, '/destination', search: FakeSearch(reverseName: 'حي أكتوبر'), here: _shaab, overrideLocation: true);
      await tapKey(tester, 'backToMap');
      await tester.drag(find.byKey(const Key('destinationMap')), const Offset(-160, 120));
      await tester.pump(const Duration(milliseconds: 100));
      expect(text(tester, 'placeTitle'), 'نحدد اسم المكان…');
      expect(enabled(tester, 'showPrice'), isFalse);
      await tester.pump(const Duration(seconds: 1));
      await settle(tester);
      expect(text(tester, 'placeTitle'), 'حي أكتوبر، المكلا');
      expect(enabled(tester, 'showPrice'), isTrue);
    });

    testWidgets('when the map cannot name a point, the rider words it, and the pickup too', (tester) async {
      final backend = await pump(tester, routes, '/destination', search: FakeSearch(fail: true), here: _shaab, overrideLocation: true);
      await tapKey(tester, 'backToMap');
      await tester.drag(find.byKey(const Key('destinationMap')), const Offset(-160, 120));
      await tester.pump(const Duration(seconds: 1));
      await settle(tester);
      expect(enabled(tester, 'showPrice'), isFalse);
      await tester.enterText(find.byKey(const Key('placeName')), 'سوق الخضار');
      await settle(tester);
      await tapKey(tester, 'showPrice');
      // The pickup still has no name for the driver.
      expect(find.byKey(const Key('confirmPickup')), findsOneWidget);
      await tester.enterText(find.byKey(const Key('placeName')), 'قرب الجامع');
      await settle(tester);
      await tapKey(tester, 'confirmPickup');
      await tapKey(tester, 'showPrice');
      await tester.pump(const Duration(seconds: 1));
      await settle(tester);
      expect(backend.seen.where((s) => s.path == 'fare-estimate'), isNotEmpty);
      expect(find.text('سوق الخضار'), findsNothing, reason: 'now on the price screen');
    });

    testWidgets('without a location the rider sets the pickup first', (tester) async {
      await pump(tester, routes, '/destination', search: FakeSearch(), overrideLocation: true);
      await tapKey(tester, 'backToMap');
      expect(find.byKey(const Key('confirmPickup')), findsOneWidget);
    });

    testWidgets('a failed search says so and leaves the map as the way out', (tester) async {
      await pump(tester, routes, '/destination', search: FakeSearch(fail: true), here: _shaab, overrideLocation: true);
      await tester.enterText(find.byKey(const Key('searchInput')), 'فوة');
      await tester.pump(const Duration(milliseconds: 400));
      await settle(tester);
      expect(find.text('تعذر البحث الآن. حرّك الخريطة لتحديد المكان.'), findsOneWidget);
      expect(find.byKey(const Key('backToMap')), findsOneWidget);
    });

    MemoryKV model3() => MemoryKV()..values['rf_destination_model'] = '3';

    testWidgets('model 3: the sheet holds the search, then shrinks to the chosen place', (tester) async {
      final backend = await pump(tester, routes, '/destination', search: FakeSearch(), here: _shaab, overrideLocation: true, prefs: model3());
      expect(find.text('إلى أين تريد الذهاب؟'), findsOneWidget);
      expect(text(tester, 'fromText'), 'موقعي الحالي، شعب البادية، المكلا');
      expect(find.byKey(const Key('pin')), findsNothing);
      expect(find.byKey(const Key('searchInput')), findsOneWidget);
      await tester.tap(find.byKey(const Key('searchInput')));
      await settle(tester);
      await tester.enterText(find.byKey(const Key('searchInput')), 'فوة');
      await tester.pump(const Duration(milliseconds: 400));
      await settle(tester);
      await tester.tap(find.byKey(const Key('hit_0')));
      await tester.pump(const Duration(seconds: 1));
      await settle(tester);
      expect(find.byKey(const Key('placeSheet')), findsNothing);
      expect(find.byKey(const Key('pin')), findsOneWidget);
      expect(text(tester, 'placeTitle'), 'فوة، المكلا');
      await tapKey(tester, 'showPrice');
      await tester.pump(const Duration(seconds: 1));
      await settle(tester);
      final body = backend.seen.firstWhere((s) => s.path == 'fare-estimate').body as Map;
      expect(body['dropoff'], {'lat': _fuwah.lat, 'lng': _fuwah.lng});
    });

    testWidgets('model 3: edit reopens the search, and choosing on the map still needs a moved pin', (tester) async {
      await pump(tester, routes, '/destination', search: FakeSearch(), here: _shaab, overrideLocation: true, prefs: model3());
      await tapKey(tester, 'backToMap');
      await tester.pump(const Duration(seconds: 1));
      expect(find.byKey(const Key('pin')), findsOneWidget);
      expect(enabled(tester, 'showPrice'), isFalse);
      await tester.drag(find.byKey(const Key('destinationMap')), const Offset(-160, 120));
      await tester.pump(const Duration(seconds: 1));
      await settle(tester);
      expect(text(tester, 'placeTitle'), 'شعب البادية، المكلا');
      expect(enabled(tester, 'showPrice'), isTrue);
      await tapKey(tester, 'editPlace');
      await tester.pump(const Duration(seconds: 1));
      expect(find.byKey(const Key('searchInput')), findsOneWidget);
    });

    testWidgets('both descriptions are optional, and are set on the price screen with the start code', (tester) async {
      final backend = await pump(tester, {
        ...routes,
        'POST rides': (_) => (201, ride('bidding')),
        'GET rides/r1': (_) => (200, ride('bidding')),
      }, '/request', extra: const RideDraft(pickup: Place('أ', _shaab), dropoff: Place('ب', _fuwah)));
      await tester.enterText(find.byKey(const Key('pickupNote')), 'عند البوابة الزرقاء');
      await tapKey(tester, 'codeSwitch');
      await tapKey(tester, 'requestOffers');
      final body = posts(backend, 'rides').single.body as Map;
      expect(body['pickup_note'], 'عند البوابة الزرقاء');
      expect(body['dropoff_note'], '');
      expect(body['require_start_code'], isTrue);
    });
  });

  group('offers', () {
    testWidgets('nothing is selected at first; choosing sends that offer with the ride version', (tester) async {
      var current = ride('bidding');
      final backend = await pump(tester, {
        'GET rides/r1': (_) => (200, current),
        'GET rides/r1/bids': (_) => (200, [offer('a', 90000), offer('b', 85000)]),
        'POST rides/r1/select': (_) {
          current = ride('match_pending', version: 4, extra: {'driver': driver(), 'match_deadline': DateTime.now().add(const Duration(seconds: 45)).toUtc().toIso8601String()});
          return (200, current);
        },
      }, '/ride/r1');
      await tester.tap(find.byKey(const Key('selectOffer')));
      await settle(tester);
      expect(posts(backend, 'rides/r1/select'), isEmpty);

      await tapKey(tester, 'offer_b');
      expect(find.textContaining('سائق-b'), findsWidgets);
      await tapKey(tester, 'selectOffer');
      final body = posts(backend, 'rides/r1/select').single.body as Map;
      expect(body['bid_id'], 'b');
      expect(body['expected_version'], 3);
      expect(find.byKey(const Key('confirming')), findsOneWidget);
    });

    testWidgets('a request without offers widens the search until the waves run out', (tester) async {
      var waves = 0;
      final backend = await pump(tester, {
        'GET rides/r1': (_) => (200, ride('requested')),
        'GET rides/r1/bids': (_) => (200, []),
        'POST rides/r1/dispatch': (_) {
          waves++;
          return waves < 3 ? (200, ride('requested')) : (422, {'code': 'max_waves_reached', 'detail': 'x'});
        },
      }, '/ride/r1');
      await tester.pump(const Duration(seconds: 29));
      expect(posts(backend, 'rides/r1/dispatch'), isEmpty);
      await tester.pump(const Duration(seconds: 2));
      await settle(tester);
      expect(posts(backend, 'rides/r1/dispatch'), hasLength(1));
      for (var i = 0; i < 12; i++) {
        await tester.pump(const Duration(seconds: 10));
        await settle(tester);
      }
      expect(posts(backend, 'rides/r1/dispatch'), hasLength(3), reason: 'nothing more after max_waves_reached');
      expect(find.byKey(const Key('searching')), findsOneWidget);
    });

    testWidgets('a request with a live offer does not widen the search', (tester) async {
      final backend = await pump(tester, {
        'GET rides/r1': (_) => (200, ride('bidding')),
        'GET rides/r1/bids': (_) => (200, [offer('a', 80000)]),
      }, '/ride/r1');
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(seconds: 10));
        await settle(tester);
      }
      expect(posts(backend, 'rides/r1/dispatch'), isEmpty);
    });

    testWidgets('sorting reorders the offers without losing the selection', (tester) async {
      await pump(tester, {
        'GET rides/r1': (_) => (200, ride('bidding')),
        'GET rides/r1/bids': (_) => (200, [offer('slow', 80000, eta: 900), offer('fast', 90000, eta: 120)]),
      }, '/ride/r1');
      double y(String id) => tester.getTopLeft(find.byKey(Key('offer_$id'))).dy;
      expect(y('slow') < y('fast'), isTrue);
      await tapKey(tester, 'offer_slow');
      await tapKey(tester, 'segment_1');
      expect(y('fast') < y('slow'), isTrue);
      expect(find.textContaining('سائق-slow'), findsWidgets);
    });

    testWidgets('an expired offer disappears and its selection is dropped', (tester) async {
      final backend = await pump(tester, {
        'GET rides/r1': (_) => (200, ride('bidding')),
        'GET rides/r1/bids': (_) => (200, [offer('soon', 80000, left: const Duration(seconds: 2)), offer('later', 90000)]),
      }, '/ride/r1');
      await tapKey(tester, 'offer_soon');
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 2200))); // expiry follows the real clock
      await tester.pump(const Duration(seconds: 1));
      await settle(tester);
      expect(find.byKey(const Key('offer_soon')), findsNothing);
      expect(find.text('انتهت مهلة هذا العرض.'), findsOneWidget);
      await tester.tap(find.byKey(const Key('selectOffer')));
      await settle(tester);
      expect(posts(backend, 'rides/r1/select'), isEmpty);
    });

    testWidgets('raising starts above the current price and can only go up', (tester) async {
      var current = ride('bidding', extra: {'rider_price_minor': 90000});
      final backend = await pump(tester, {
        'GET rides/r1': (_) => (200, current),
        'POST rides/r1/raise-price': (_) {
          current = ride('bidding', version: 4, extra: {'rider_price_minor': 95000});
          return (200, current);
        },
      }, '/ride/r1');
      await tapKey(tester, 'raisePrice');
      expect(tester.widget<IconButton>(find.byKey(const Key('priceDown'))).onPressed, isNull);
      expect(find.text('بدون سعر'), findsNothing);
      await tester.tap(find.byKey(const Key('usePrice')));
      await tester.pump(const Duration(seconds: 1));
      await settle(tester);
      final body = posts(backend, 'rides/r1/raise-price').single.body as Map;
      expect(body['amount_minor'], 95000);
      expect(body['expected_version'], 3);
    });

    testWidgets('cancelling needs a reason and sends its code', (tester) async {
      final backend = await pump(tester, {
        'GET rides/r1': (_) => (200, ride('bidding')),
        'POST rides/r1/cancel': (_) => (200, ride('cancelled', actions: [], extra: {'cancellation': {'by_role': 'rider'}})),
      }, '/ride/r1');
      await tapKey(tester, 'rideMenu');
      await tester.tap(find.byKey(const Key('cancelItem')));
      await tester.pump(const Duration(seconds: 1));
      await settle(tester);
      await tester.tap(find.byKey(const Key('confirmCancel')));
      await settle(tester);
      expect(posts(backend, 'rides/r1/cancel'), isEmpty);
      await tester.tap(find.byKey(const Key('reason_changed_mind')));
      await settle(tester);
      await tester.tap(find.byKey(const Key('confirmCancel')));
      await tester.pump(const Duration(seconds: 1));
      await settle(tester);
      expect((posts(backend, 'rides/r1/cancel').single.body as Map)['reason_code'], 'changed_mind');
    });

    testWidgets('a request that expired offers to send it again', (tester) async {
      await pump(tester, {
        'GET rides/r1': (_) => (200, ride('cancelled', actions: [], extra: {'rider_price_minor': 90000, 'cancellation': {'by_role': 'system'}})),
      }, '/ride/r1');
      expect(find.byKey(const Key('noOffers')), findsOneWidget);
      expect(find.byKey(const Key('requestHigher')), findsOneWidget);
    });
  });

  group('the trip', () {
    Map<String, dynamic> withDriver(String status, {Map<String, dynamic> extra = const {}, List<String> actions = const ['rider_cancel']}) => ride(status, actions: actions, extra: {'driver': driver(phone: '+967700000009'), 'agreed_fare_minor': 85000, ...extra});

    testWidgets('confirmed, then the driver, plate and start code; no code when not required', (tester) async {
      await pump(tester, {'GET rides/r1': (_) => (200, withDriver('assigned', extra: {'start_code': '4821', 'start_code_required': true}))}, '/ride/r1');
      expect(find.byKey(const Key('tripConfirmed')), findsOneWidget);
      await tapKey(tester, 'followDriver');
      expect(find.text('السائق في الطريق'), findsOneWidget);
      expect(find.byKey(const Key('plate')), findsOneWidget);
      expect(find.text('4821'), findsOneWidget);
    });

    testWidgets('no start code card when the ride has none', (tester) async {
      await pump(tester, {'GET rides/r1': (_) => (200, withDriver('en_route'))}, '/ride/r1');
      expect(find.byKey(const Key('startCode')), findsNothing);
    });

    testWidgets('the rider cannot cancel once the trip started: the server decides', (tester) async {
      await pump(tester, {'GET rides/r1': (_) => (200, withDriver('in_progress', actions: []))}, '/ride/r1');
      expect(find.byKey(const Key('rideMenu')), findsNothing);
      expect(find.text('السوق المركزي'), findsOneWidget);
    });

    testWidgets('emergency stays off until the operator sets a number', (tester) async {
      final apps = FakeApps();
      final backend = await pump(tester, {'GET rides/r1': (_) => (200, withDriver('en_route'))}, '/ride/r1', apps: apps);
      await tapKey(tester, 'emergency');
      expect(apps.dialed, isEmpty);
      expect(posts(backend, 'rides/r1/emergency'), isEmpty);
      expect(find.text('لم يحدد المشغّل رقم الطوارئ بعد.'), findsOneWidget);
    });

    testWidgets('emergency calls first and tells the operator', (tester) async {
      final apps = FakeApps();
      final backend = await pump(tester, {
        'GET rides/r1': (_) => (200, withDriver('en_route', extra: {'emergency_phone': '+967199'})),
        'POST rides/r1/emergency': (_) => (200, {'recorded': true, 'emergency_phone': '+967199'}),
      }, '/ride/r1', apps: apps);
      await tapKey(tester, 'emergency');
      await tester.tap(find.byKey(const Key('emergencyGo')));
      await settle(tester);
      expect(apps.dialed, ['+967199']);
      expect(posts(backend, 'rides/r1/emergency'), hasLength(1));
    });

    testWidgets('sharing says so when there is no page for the link yet', (tester) async {
      await pump(tester, {
        'GET rides/r1': (_) => (200, withDriver('en_route')),
        'POST rides/r1/share': (_) => (201, {'token': 't', 'url': null}),
      }, '/ride/r1');
      await tapKey(tester, 'share');
      expect(find.text('صفحة مشاركة الرحلة غير جاهزة بعد.'), findsOneWidget);
    });
  });

  group('the end', () {
    Map<String, dynamic> done({int? stars, String? paid}) => ride('completed', actions: [], extra: {
          'driver': driver(),
          'cash': {'amount_minor': 85000, 'rider_confirmed_at': paid},
          if (stars != null) 'my_rating': {'stars': stars},
          'timestamps': {},
        });

    testWidgets('paying and rating with tags and a note', (tester) async {
      var current = done();
      final backend = await pump(tester, {
        'GET rides/r1': (_) => (200, current),
        'POST rides/r1/cash-confirm': (_) {
          current = done(paid: '2026-11-02T10:00:00Z');
          return (200, current);
        },
        'POST rides/r1/rating': (_) => (201, {}),
      }, '/ride/r1');
      await tapKey(tester, 'paid');
      expect(posts(backend, 'rides/r1/cash-confirm'), hasLength(1));
      expect(find.text('أكدت الدفع'), findsOneWidget);
      await tapKey(tester, 'rateTrip');
      await tapKey(tester, 'rate_5');
      await tapKey(tester, 'tag_safe_driving');
      await tester.enterText(find.byKey(const Key('ratingNote')), 'ممتاز');
      await tester.pump();
      await tapKey(tester, 'sendRating');
      final body = posts(backend, 'rides/r1/rating').single.body as Map;
      expect(body['stars'], 5);
      expect(body['tags'], ['safe_driving']);
      expect(body['comment'], 'ممتاز');
    });

    testWidgets('the receipt shows the reference and fare, and reports reach the operator', (tester) async {
      final backend = await pump(tester, {
        'GET rides/r1': (_) => (200, {...done(stars: 5), 'id': 'abcdef12-0000'}),
        'POST rides/r1/disputes': (_) => (201, {}),
      }, '/receipt/r1');
      expect(find.text('RF-ABCDEF12'), findsOneWidget);
      expect(find.text('850 YER'), findsOneWidget);
      await tapKey(tester, 'reportProblem');
      await tester.enterText(find.byKey(const Key('problemText')), 'خلاف على الأجرة');
      await tester.tap(find.byKey(const Key('sendProblem')));
      await settle(tester);
      expect((posts(backend, 'rides/r1/disputes').single.body as Map)['description'], 'خلاف على الأجرة');
    });
  });

  group('history and account', () {
    testWidgets('past and current trips are separate, and an unrated trip asks for a rating', (tester) async {
      await pump(tester, {
        'GET rides': (_) => (200, {
              'results': [
                {...ride('completed', actions: []), 'id': 'old', 'agreed_fare_minor': 85000},
                {...ride('bidding'), 'id': 'now'},
              ]
            }),
      }, '/rides');
      expect(find.byKey(const Key('ride_old')), findsOneWidget);
      expect(find.byKey(const Key('ride_now')), findsNothing);
      expect(find.text('قيّم رحلتك'), findsOneWidget);
      await tapKey(tester, 'segment_1');
      expect(find.byKey(const Key('ride_now')), findsOneWidget);
      expect(find.byKey(const Key('ride_old')), findsNothing);
    });

    testWidgets('deleting an account asks for a fresh code first', (tester) async {
      final backend = await pump(tester, {
        'GET me/trust': (_) => (200, {'rating_avg': 4.7, 'rating_provisional': false}),
        'POST auth/otp/request': (_) => (200, {}),
        'POST me/delete-account': (_) => (204, null),
      }, '/account');
      await tester.scrollUntilVisible(find.byKey(const Key('deleteAccount')), 200, scrollable: find.byType(Scrollable).first);
      await tapKey(tester, 'deleteAccount');
      expect(posts(backend, 'me/delete-account'), isEmpty);
      await tester.tap(find.byKey(const Key('sendDeleteCode')));
      await settle(tester);
      expect((posts(backend, 'auth/otp/request').single.body as Map)['phone'], '+967711000001');
      await tester.enterText(find.byKey(const Key('deleteCode')), '123456');
      await tester.tap(find.byKey(const Key('confirmDelete')));
      await settle(tester);
      expect((posts(backend, 'me/delete-account').single.body as Map)['code'], '123456');
    });

    testWidgets('the always-on code and font choices are saved on the phone', (tester) async {
      final prefs = MemoryKV();
      await pump(tester, {'GET me/trust': (_) => (200, {'rating_provisional': true})}, '/account', prefs: prefs);
      await tapKey(tester, 'alwaysCode');
      expect(prefs.values['rf_always_code'], '1');
      await tapKey(tester, 'fontRow');
      await tester.tap(find.byKey(const Key('font_Tajawal')));
      await tester.pump(const Duration(seconds: 1));
      await settle(tester);
      expect(prefs.values['rf_font'], 'Tajawal');
      await tapKey(tester, 'destinationModelRow');
      await tester.tap(find.byKey(const Key('destinationModel_3')));
      await tester.pump(const Duration(seconds: 1));
      await settle(tester);
      expect(prefs.values['rf_destination_model'], '3');
      await tapKey(tester, 'appearanceRow');
      await tester.tap(find.byKey(const Key('appearance_night')));
      await tester.pump(const Duration(seconds: 1));
      await settle(tester);
      expect(prefs.values['rf_appearance'], 'night');
    });
  });

  testWidgets('switching the appearance recolours the screen already on show', (tester) async {
    addTearDown(() => RfColors.use(RfAppearance.day));
    final prefs = MemoryKV();
    final scope = ProviderContainer(overrides: [
      sessionStoreProvider.overrideWithValue(SessionStore(MemoryKV())),
      prefsProvider.overrideWithValue(prefs),
    ]);
    addTearDown(scope.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(container: scope, child: const RiderApp()));
    await settle(tester);
    Iterable<Color?> textColours() => tester.widgetList<Text>(find.byType(Text)).map((w) => w.style?.color).whereType<Color>();
    expect(textColours(), contains(RfPalette.day.text));

    await scope.read(appearanceProvider.notifier).set(RfAppearance.night);
    await settle(tester);

    expect(RfColors.isNight, isTrue);
    expect(prefs.values['rf_appearance'], 'night');
    expect(textColours(), isNot(contains(RfPalette.day.text)));
    expect(textColours(), contains(RfPalette.night.text));
    expect(Theme.of(tester.element(find.byType(Scaffold).first)).brightness, Brightness.dark);
  });
}
