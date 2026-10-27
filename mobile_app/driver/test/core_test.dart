import 'package:flutter_gen/gen_l10n/app_localizations_ar.dart';
import 'package:flutter_gen/gen_l10n/app_localizations_en.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rideflow_driver/core/api/api_client.dart';
import 'package:rideflow_driver/core/api/api_exception.dart';
import 'package:rideflow_driver/core/auth/session_store.dart';
import 'package:rideflow_driver/core/format.dart';
import 'package:rideflow_driver/core/realtime/events_socket.dart';
import 'package:rideflow_driver/data/driver_api.dart';
import 'package:rideflow_driver/data/models.dart';
import 'package:rideflow_driver/features/history/history_screens.dart';
import 'package:rideflow_driver/shared/labels.dart';

import 'support/fake_backend.dart';

Future<(ApiClient, FakeBackend, SessionStore)> clientWith(Map<String, Handler> routes, {Tokens? tokens}) async {
  final backend = FakeBackend(routes);
  final store = SessionStore(MemoryKV());
  if (tokens != null) await store.save(tokens);
  return (ApiClient(session: store, dio: backend.dio(), appClientId: 'test-driver'), backend, store);
}

void main() {
  group('ApiClient', () {
    test('sends app context, bearer token and an idempotency key on writes', () async {
      final (client, backend, _) = await clientWith({'POST driver/availability': (_) => (200, {'eligible': true})}, tokens: const Tokens('a1', 'r1'));
      await client.post('driver/availability', data: {'online': true}, actionKey: 'key-1');
      final h = backend.seen.single.headers;
      expect(h['X-RideFlow-App'], 'test-driver');
      expect(h['Authorization'], 'Bearer a1');
      expect(h['Idempotency-Key'], 'key-1');
    });

    test('concurrent 401s share ONE refresh (rotating refresh tokens are single-use) and retry with the same key', () async {
      var refreshes = 0;
      final (client, backend, store) = await clientWith({
        'GET me': (r) => r.headers['Authorization'] == 'Bearer a2' ? (200, {'ok': 1}) : (401, {'code': 'token_not_valid'}),
        'POST rides/x/confirm': (r) => r.headers['Authorization'] == 'Bearer a2' ? (200, {'id': 'x'}) : (401, {'code': 'token_not_valid'}),
        'POST auth/token/refresh': (r) {
          refreshes++;
          return (r.body as Map)['refresh'] == 'r1' ? (200, {'access': 'a2', 'refresh': 'r2'}) : (401, {'code': 'token_not_valid'});
        },
      }, tokens: const Tokens('a1', 'r1'));
      await Future.wait([client.get('me'), client.get('me'), client.post('rides/x/confirm', actionKey: 'k-confirm')]);
      expect(refreshes, 1);
      expect((await store.read())!.refresh, 'r2');
      final confirms = backend.seen.where((s) => s.path == 'rides/x/confirm').toList();
      expect(confirms.map((s) => s.headers['Idempotency-Key']).toSet(), {'k-confirm'});
    });

    test('rejected refresh clears the session and reports expiry', () async {
      var expired = false;
      final (client, _, store) = await clientWith({
        'GET me': (_) => (401, {'code': 'token_not_valid'}),
        'POST auth/token/refresh': (_) => (401, {'code': 'token_not_valid'}),
      }, tokens: const Tokens('a1', 'r1'));
      client.onSessionExpired = () => expired = true;
      await expectLater(client.get('me'), throwsA(isA<ApiException>().having((e) => e.status, 'status', 401)));
      expect(expired, isTrue);
      expect(await store.read(), isNull);
    });

    test('eligibility refusal exposes the backend reasons', () async {
      final (client, _, _) = await clientWith({
        'POST driver/availability': (_) => (403, {
              'code': 'not_eligible',
              'detail': {'detail': 'Driver is not eligible.', 'reasons': ['subscription_inactive', 'no_approved_vehicle']}
            }),
      }, tokens: const Tokens('a', 'r'));
      final e = await DriverApi(client).setAvailability(true).then<ApiException?>((_) => null, onError: (Object e) => e as ApiException);
      expect(e!.code, 'not_eligible');
      expect(e.reasons, ['subscription_inactive', 'no_approved_vehicle']);
    });

    test('transition posts expected_version to the mapped endpoint', () async {
      final (client, backend, _) = await clientWith({
        'POST rides/r1/en-route': (_) => (200, {'id': 'r1', 'status': 'en_route', 'version': 5}),
      }, tokens: const Tokens('a', 'r'));
      final ride = Ride({'id': 'r1', 'status': 'assigned', 'version': 4, 'viewer_role': 'driver', 'allowed_actions': ['en_route']});
      final next = await DriverApi(client).transition(ride, 'en_route', actionKey: 'k');
      expect((backend.seen.single.body as Map)['expected_version'], 4);
      expect(next.status, 'en_route');
    });
  });

  group('EventsSocket', () {
    test('drops duplicate hints (replay overlapping live) and persists the cursor for resume', () async {
      final store = SessionStore(MemoryKV());
      final socket = EventsSocket(session: store);
      final got = <int>[];
      final sub = socket.hints.listen((h) => got.add(h.cursor));
      socket.debugReceive('{"type":"hint","cursor":7,"kind":"ride.offer","payload":{"ride_id":"x"}}');
      socket.debugReceive('{"type":"hint","cursor":7,"kind":"ride.offer","payload":{"ride_id":"x"}}');
      socket.debugReceive('{"type":"hint","cursor":8,"kind":"ride.selected","payload":{}}');
      socket.debugReceive('not json');
      await Future<void>.delayed(Duration.zero);
      expect(got, [7, 8]);
      expect(socket.lastCursor, 8);
      expect(await store.readCursor(), 8);
      await sub.cancel();
    });
  });

  group('models and formatting', () {
    test('ride parses viewer role, allowed actions, bid and cash', () {
      final r = Ride({
        'id': 'r',
        'status': 'completed',
        'version': 9,
        'viewer_role': 'driver',
        'allowed_actions': ['dispute'],
        'currency': 'YER',
        'agreed_fare_minor': 150000,
        'estimate': {'min_minor': 100000, 'max_minor': 140000, 'distance_m': 3200},
        'my_bid': {'id': 'b', 'amount_minor': 150000, 'eta_seconds': 300, 'status': 'accepted'},
        'cash': {'amount_minor': 150000, 'driver_confirmed_at': null},
        'timestamps': {'completed_at': '2026-10-25T10:00:00Z'},
      });
      expect(r.allowedActions, {'dispute'});
      expect(r.myBid!.status, 'accepted');
      expect(r.driverCashConfirmed, isFalse);
      expect(r.isActiveForDriver, isFalse);
    });

    test('money uses integer minor units and Latin digits', () {
      expect(formatMoney(150000, 'YER', 2), '1,500 YER');
      expect(inputToMinor('1500', 2), 150000);
      expect(inputToMinor('0', 2), isNull);
      expect(minorToInput(150050, 2), '1500.50');
    });

    test('earnings only count completed rides where this user is the driver', () {
      final now = DateTime.now();
      Ride ride(String status, String role, int fare, DateTime at) => Ride({
            'id': '$status$role$fare',
            'status': status,
            'viewer_role': role,
            'agreed_fare_minor': fare,
            'timestamps': {'completed_at': at.toUtc().toIso8601String()},
          });
      final s = summarize([
        ride('completed', 'driver', 1000, now),
        ride('completed', 'candidate', 9999, now),
        ride('cancelled', 'driver', 5000, now),
        ride('completed', 'driver', 2000, now.subtract(const Duration(days: 40))),
      ], now.subtract(const Duration(days: 30)));
      expect(s.count, 1);
      expect(s.total, 1000);
    });

    test('eligibility reasons are localized in both languages, unknown codes stay visible', () {
      final ar = AppLocalizationsAr(), en = AppLocalizationsEn();
      expect(eligibilityReason(en, 'subscription_inactive'), 'No active subscription.');
      expect(eligibilityReason(ar, 'documents_missing_or_expired:insurance'), contains('وثائق'));
      expect(eligibilityReason(en, 'restricted_until:2026-11-01T10:00:00+03:00'), contains('2026-11-01 10:00'));
      expect(eligibilityReason(en, 'brand_new_reason'), contains('brand_new_reason'));
    });
  });
}
