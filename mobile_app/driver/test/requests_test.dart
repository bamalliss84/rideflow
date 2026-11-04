import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rideflow_driver/app/providers.dart';
import 'package:rideflow_driver/core/api/api_client.dart';
import 'package:rideflow_driver/core/auth/session_store.dart';
import 'package:rideflow_driver/core/location/location_service.dart';
import 'package:rideflow_driver/core/realtime/events_socket.dart';
import 'package:rideflow_driver/data/models.dart';
import 'package:rideflow_driver/design/theme.dart';
import 'package:rideflow_driver/features/home/home_screen.dart';

import 'support/fake_backend.dart';

class _NoSocket extends EventsSocket {
  _NoSocket(SessionStore s) : super(session: s);
  @override
  Future<void> start() async {}
}

class _FixedLocation extends LocationService {
  @override
  Future<LocationAccess> access({bool request = true}) async => LocationAccess.granted;
  @override
  Future<Fix?> current() async => Fix(lat: 14.5, lng: 49.1, accuracy: 8, deviceTs: DateTime.now());
  @override
  void start({
    required Future<void> Function(Fix fix) onFix,
    required void Function(Object error) onError,
    Duration minInterval = const Duration(seconds: 10),
    Duration heartbeat = const Duration(seconds: 30),
  }) {}
  @override
  void stop() {}
}

Map<String, dynamic> offer(String id, {int? riderPrice, Map<String, dynamic>? bid, int ratingCount = 0}) => {
      'id': id,
      'status': 'bidding',
      'version': 2,
      'viewer_role': 'candidate',
      'allowed_actions': ['bid'],
      'pickup_landmark': 'الشرج $id',
      'dropoff_landmark': 'السوق',
      'currency': 'YER',
      'rider_price_minor': riderPrice,
      'my_bid': bid,
      'estimate': {'min_minor': 73500, 'max_minor': 110300, 'distance_m': 2100, 'bid_step_minor': 5000},
      'rider': {
        'display_name': 'أحمد',
        'trust': {'rating_avg': 4.5, 'rating_count': ratingCount, 'rating_provisional': ratingCount < 5, 'completed_rides': 48, 'completion_rate': 0.96},
      },
      'timestamps': {},
    };

Widget _app(FakeBackend backend, SessionStore store, Widget child) => ProviderScope(
      overrides: [
        sessionStoreProvider.overrideWithValue(store),
        apiClientProvider.overrideWith((ref) => ApiClient(session: store, dio: backend.dio(), appClientId: 'test-driver')),
        eventsSocketProvider.overrideWith((ref) => _NoSocket(store)),
        locationServiceProvider.overrideWithValue(_FixedLocation()),
      ],
      child: MaterialApp(
        theme: buildRideFlowTheme(),
        locale: const Locale('ar'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: const [AppLocalizations.delegate, GlobalMaterialLocalizations.delegate, GlobalWidgetsLocalizations.delegate, GlobalCupertinoLocalizations.delegate],
        home: child,
      ),
    );

Future<void> _settle(WidgetTester tester, [int ticks = 12]) async {
  for (var i = 0; i < ticks; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void _phone(WidgetTester tester) {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 2.75;
  addTearDown(tester.view.reset);
}

Future<SessionStore> _session() async {
  final store = SessionStore(MemoryKV());
  await store.save(const Tokens('a', 'r'));
  return store;
}

void main() {
  group('offer sheet', () {
    testWidgets('starts at the rider price; changing it turns "accept" into the driver\'s own offer', (tester) async {
      _phone(tester);
      final posted = <Object?>[];
      final backend = FakeBackend({
        'POST rides/r1/bids': (r) {
          posted.add(r.body);
          return (201, {'id': 'b1', 'amount_minor': 85000, 'eta_seconds': 300, 'status': 'open'});
        },
      });
      await tester.pumpWidget(_app(backend, await _session(), Scaffold(body: BidSheet(ride: Ride(offer('r1', riderPrice: 80000)), minorUnits: 2))));
      await _settle(tester, 2);

      expect(find.text('اقبل 800 YER'), findsOneWidget);
      expect(find.text('مطابق لسعر الراكب'), findsOneWidget);

      await tester.tap(find.byKey(const Key('pricePlus')));
      await _settle(tester, 2);
      expect(find.text('أرسل عرض 850 YER'), findsOneWidget);
      expect(find.textContaining('أعلى من سعر الراكب'), findsOneWidget);

      await tester.ensureVisible(find.byKey(const Key('sendBid')));
      await tester.tap(find.byKey(const Key('sendBid')));
      await _settle(tester, 4);
      expect((posted.single as Map)['amount_minor'], 85000);
      expect((posted.single as Map)['eta_seconds'], 300);
    });

    testWidgets('without a rider price: starts at the estimate and says where the price stands', (tester) async {
      _phone(tester);
      await tester.pumpWidget(_app(FakeBackend({}), await _session(), Scaffold(body: BidSheet(ride: Ride(offer('r1')), minorUnits: 2))));
      await _settle(tester, 2);
      expect(find.text('ضمن التقدير'), findsOneWidget);
      await tester.tap(find.byKey(const Key('priceMinus')));
      await _settle(tester, 2);
      expect(find.text('أقل من التقدير'), findsOneWidget);
    });

    testWidgets('a lost connection keeps the price, and resending reuses the same idempotency key', (tester) async {
      _phone(tester);
      var attempts = 0;
      final backend = FakeBackend({
        'POST rides/r1/bids': (_) {
          attempts++;
          if (attempts == 1) throw DioException(requestOptions: RequestOptions(path: 'x'), type: DioExceptionType.connectionError);
          return (201, {'id': 'b1', 'amount_minor': 80000, 'eta_seconds': 300, 'status': 'open'});
        },
      });
      await tester.pumpWidget(_app(backend, await _session(), Scaffold(body: BidSheet(ride: Ride(offer('r1', riderPrice: 80000)), minorUnits: 2))));
      await _settle(tester, 2);

      await tester.ensureVisible(find.byKey(const Key('sendBid')));
      await tester.tap(find.byKey(const Key('sendBid')));
      await _settle(tester, 4);
      expect(find.text('لم يصل عرضك بعد'), findsOneWidget);
      expect(find.text('إعادة الإرسال'), findsOneWidget);
      expect(find.widgetWithText(TextField, '800'), findsOneWidget);

      await tester.ensureVisible(find.byKey(const Key('sendBid')));
      await tester.tap(find.byKey(const Key('sendBid')));
      await _settle(tester, 4);
      final keys = backend.seen.where((s) => s.path == 'rides/r1/bids').map((s) => s.headers['Idempotency-Key']).toList();
      expect(keys, hasLength(2));
      expect(keys.first, keys.last);
    });

    testWidgets('errors explain themselves: open offers limit and a request that is gone', (tester) async {
      _phone(tester);
      var code = 'open_bid_limit';
      final backend = FakeBackend({
        'POST rides/r1/bids': (_) => (code == 'open_bid_limit' ? 422 : 409, {'code': code, 'detail': 'x'}),
        'GET driver/ride-offers': (_) => (200, []),
      });
      await tester.pumpWidget(_app(backend, await _session(), Scaffold(body: BidSheet(ride: Ride(offer('r1')), minorUnits: 2))));
      await _settle(tester, 2);
      await tester.ensureVisible(find.byKey(const Key('sendBid')));
      await tester.tap(find.byKey(const Key('sendBid')));
      await _settle(tester, 4);
      expect(find.text('وصلت حد العروض المفتوحة'), findsOneWidget);
      expect(find.byKey(const Key('openMine')), findsOneWidget);
      expect(find.byKey(const Key('sendBid')), findsNothing);

      code = 'bidding_closed';
      await tester.pumpWidget(_app(backend, await _session(), Scaffold(key: UniqueKey(), body: BidSheet(key: UniqueKey(), ride: Ride(offer('r1')), minorUnits: 2))));
      await _settle(tester, 2);
      await tester.ensureVisible(find.byKey(const Key('sendBid')));
      await tester.tap(find.byKey(const Key('sendBid')));
      await _settle(tester, 4);
      expect(find.byKey(const Key('requestGone')), findsOneWidget);
    });
  });

  group('requests list', () {
    Future<(FakeBackend, List<Map<String, dynamic>> Function())> pumpHome(WidgetTester tester, List<Map<String, dynamic>> offers) async {
      _phone(tester);
      var current = offers;
      var hidden = <Map<String, dynamic>>[];
      final backend = FakeBackend({
        'GET me': (_) => (200, {
              'user': {'id': 'u', 'phone': '+967700000001', 'full_name': 'سالم'},
              'tenant': {'tenant_name': 'مشغل', 'roles': ['driver']},
              'currency': 'YER',
              'currency_minor_units': 2,
            }),
        'GET driver/eligibility': (_) => (200, {
              'eligible': true,
              'reasons': [],
              'subscription_active': true,
              'status': 'approved',
              'is_online': true,
              'max_open_bids': 5,
              'presence': {'has_location': true, 'fresh': true, 'server_ts': DateTime.now().toUtc().toIso8601String()},
            }),
        'GET rides': (_) => (200, {'results': []}),
        'GET driver/ride-offers': (_) => (200, current),
        'GET driver/ride-offers/hidden': (_) => (200, {'count': hidden.length}),
        'DELETE driver/ride-offers/hidden': (_) {
          current = [...current, ...hidden];
          hidden = [];
          return (204, null);
        },
        'POST driver/ride-offers/r2/hide': (_) {
          hidden = current.where((o) => o['id'] == 'r2').toList();
          current = current.where((o) => o['id'] != 'r2').toList();
          return (204, null);
        },
        'DELETE driver/ride-offers/r2/hide': (_) {
          current = [...current, ...hidden];
          hidden = [];
          return (204, null);
        },
        'POST rides/r3/bids/b3/withdraw': (_) {
          current = current.where((o) => o['id'] != 'r3').toList();
          return (200, {});
        },
      });
      await tester.pumpWidget(_app(backend, await _session(), const HomeScreen()));
      await _settle(tester, 15);
      return (backend, () => current);
    }

    testWidgets('card shows rating and price; tapping reveals the right actions; "new" replaces the prior', (tester) async {
      await pumpHome(tester, [offer('r1', riderPrice: 80000, ratingCount: 32), offer('r2')]);

      expect(find.byKey(const Key('statusReady')), findsOneWidget);
      expect(find.text('سعر الراكب'), findsOneWidget);
      expect(find.text('4.5'), findsOneWidget); // only the rated rider
      expect(find.text('(32)'), findsOneWidget);
      expect(find.text('جديد'), findsOneWidget); // the other rider: no fake 4.5
      expect(find.text('735–1,103'), findsNWidgets(2)); // estimate shown beside the rider price too

      expect(find.byKey(const Key('makeOffer_r1')), findsNothing);
      await tester.tap(find.byKey(const Key('toggleCard_r1')));
      await _settle(tester, 2);
      expect(find.text('اقبل 800 YER'), findsOneWidget);
      expect(find.text('قدّم سعرًا آخر'), findsOneWidget);
      expect(find.byKey(const Key('hide_r1')), findsOneWidget);

      await tester.tap(find.byKey(const Key('toggleCard_r2')));
      await _settle(tester, 2);
      expect(find.byKey(const Key('makeOffer_r1')), findsNothing); // one open at a time
      expect(find.text('قدّم عرضك'), findsOneWidget);

      await tester.tap(find.byKey(const Key('tab_price')));
      await _settle(tester, 2);
      expect(find.byKey(const Key('toggleCard_r2')), findsNothing);
      expect(find.byKey(const Key('toggleCard_r1')), findsOneWidget);
    });

    testWidgets('hide removes the card with an undo; an empty list offers to show hidden requests', (tester) async {
      final (backend, _) = await pumpHome(tester, [offer('r2')]);
      await tester.tap(find.byKey(const Key('toggleCard_r2')));
      await _settle(tester, 2);
      await tester.tap(find.byKey(const Key('hide_r2')));
      await _settle(tester, 8);
      expect(find.byKey(const Key('toggleCard_r2')), findsNothing);
      expect(find.text('أخفينا الطلب من قائمتك'), findsOneWidget);
      expect(find.byKey(const Key('showHidden')), findsOneWidget);

      await tester.tap(find.text('تراجع'));
      await _settle(tester, 8);
      expect(backend.seen.any((s) => s.method == 'DELETE' && s.path == 'driver/ride-offers/r2/hide'), isTrue);
      expect(find.byKey(const Key('toggleCard_r2')), findsOneWidget);
    });

    testWidgets('an open offer moves to "my offers", shows the status bar, and can be withdrawn', (tester) async {
      final bid = {
        'id': 'b3',
        'amount_minor': 160000,
        'eta_seconds': 300,
        'status': 'open',
        'created_at': DateTime.now().toUtc().toIso8601String(),
        'expires_at': DateTime.now().add(const Duration(seconds: 100)).toUtc().toIso8601String(),
      };
      await pumpHome(tester, [offer('r3', bid: bid), offer('r4')]);

      expect(find.byKey(const Key('toggleCard_r3')), findsNothing);
      expect(find.byKey(const Key('toggleCard_r4')), findsOneWidget);
      expect(find.byKey(const Key('offersBar')), findsOneWidget);
      expect(find.text('عرضك 1,600 YER'), findsOneWidget);

      await tester.tap(find.byKey(const Key('offersBar')));
      await _settle(tester, 3);
      expect(find.byKey(const Key('myOffer_r3')), findsOneWidget);
      expect(find.descendant(of: find.byKey(const Key('offerClock_r3')), matching: find.byType(CircularProgressIndicator)), findsOneWidget);
      expect(find.descendant(of: find.byKey(const Key('myOffer_r3')), matching: find.byType(LinearProgressIndicator)), findsNothing);
      expect(find.byKey(const Key('offersBar')), findsNothing);
      expect(find.text('1 من 5'), findsOneWidget);

      await tester.tap(find.byKey(const Key('withdraw_r3')));
      await _settle(tester, 8);
      expect(find.byKey(const Key('myOffer_r3')), findsNothing);
      expect(find.text('لا توجد عروض مفتوحة.'), findsOneWidget);
    });
  });
}
