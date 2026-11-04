// A whole trip against the running local stack, with the driver played through the API. Skipped unless LIVE_API_URL is set.
//   LIVE_API_URL=http://127.0.0.1:8010 flutter test test/live
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rideflow_rider/core/api/api_client.dart';
import 'package:rideflow_rider/core/auth/session_store.dart';
import 'package:rideflow_rider/data/models.dart';
import 'package:rideflow_rider/data/rider_api.dart';

final _base = Platform.environment['LIVE_API_URL'];
final _code = Platform.environment['LIVE_OTP_CODE'] ?? '000000';
const _riderPhone = '+967711000002';
const _driverPhone = '+967700000001';
const _center = Point(14.5426, 49.1242);

Future<RiderApi> _rider() async {
  final store = SessionStore(MemoryKV());
  final client = ApiClient(session: store, dio: Dio(BaseOptions(baseUrl: '$_base/api/v1/', validateStatus: (_) => true)), appClientId: 'demo-mukalla-rider');
  final api = RiderApi(client);
  await api.requestOtp(_riderPhone);
  final tokens = await api.verifyOtp(_riderPhone, _code);
  await store.save(Tokens(tokens['access'] as String, tokens['refresh'] as String));
  return api;
}

Future<ApiClient> _driver() async {
  final store = SessionStore(MemoryKV());
  final client = ApiClient(session: store, dio: Dio(BaseOptions(baseUrl: '$_base/api/v1/', validateStatus: (_) => true)), appClientId: 'demo-mukalla-driver');
  await client.post('auth/otp/request', data: {'phone': _driverPhone}, auth: false);
  final tokens = await client.post('auth/otp/verify', data: {'phone': _driverPhone, 'code': _code}, auth: false) as Map;
  await store.save(Tokens(tokens['access'] as String, tokens['refresh'] as String));
  return client;
}

void main() {
  test(
    'request, offer, select, confirm, follow, share, start with a code, finish, pay and rate',
    () async {
      final rider = await _rider();
      final driver = await _driver();

      Future<void> report() => driver.post('driver/location', data: {'lat': _center.lat, 'lng': _center.lng, 'accuracy_m': 8, 'device_ts': DateTime.now().toUtc().toIso8601String()});
      await driver.post('driver/availability', data: {'online': true}).catchError((_) => null);
      await report();

      for (final old in await rider.rides()) {
        if (old.canCancel) await rider.cancel(old, code: 'other', reason: 'live test cleanup');
      }

      const pickup = Place('قرب جامع المحضار', _center);
      const dropoff = Place('سوق المكلا المركزي', Point(14.5526, 49.1342));
      final estimate = await rider.estimate(pickup.point, dropoff.point);
      expect(estimate.maxMinor, greaterThan(estimate.minMinor));

      var ride = await rider.createRide(RideDraft(pickup: pickup, dropoff: dropoff, requireCode: true, priceMinor: estimate.riderMinMinor), actionKey: newActionKey());
      expect(ride.riderPriceMinor, estimate.riderMinMinor);
      ride = await rider.raisePrice(ride, estimate.maxMinor);
      expect(ride.riderPriceMinor, estimate.maxMinor);

      await driver.post('rides/${ride.id}/bids', data: {'amount_minor': estimate.maxMinor, 'eta_seconds': 240});
      final offers = await rider.offers(ride.id);
      expect(offers.single.driver?.vehicle?.plate, isNull, reason: 'no plate before the match');
      ride = await rider.ride(ride.id);
      ride = await rider.select(ride, offers.single.id, actionKey: newActionKey());
      expect(ride.status, 'match_pending');

      Future<Map> act(String path, [Map<String, dynamic> extra = const {}]) async {
        final fresh = await rider.ride(ride.id);
        return await driver.post('rides/${ride.id}/$path', data: {'expected_version': fresh.version, ...extra}) as Map;
      }

      await act('confirm');
      ride = await rider.ride(ride.id);
      expect(ride.driver?.vehicle?.plate, isNotNull);
      expect(ride.driver?.phone, isNotNull);
      expect(ride.startCode, hasLength(4));
      expect(ride.freeCancelUntil, isNotNull);

      expect((await rider.driverPosition(ride.id)).stale, isFalse);
      await rider.share(ride.id); // the link's page isn't built; the API call must still succeed
      expect((await rider.ride(ride.id)).shareActive, isTrue);
      await rider.stopSharing(ride.id);

      await act('en-route');
      await act('arrive', {'lat': _center.lat, 'lng': _center.lng, 'accuracy_m': 8, 'device_ts': DateTime.now().toUtc().toIso8601String()});
      await act('start', {'start_code': ride.startCode});
      expect((await rider.ride(ride.id)).status, 'in_progress');
      await act('complete');

      ride = await rider.confirmCash(ride.id, actionKey: newActionKey());
      expect(ride.status, 'completed');
      expect(ride.cashConfirmedByMe, isTrue);
      await rider.rate(ride.id, 5, tags: ['safe_driving'], comment: 'live test', actionKey: newActionKey());
      expect((await rider.ride(ride.id)).myRatingStars, 5);
      expect((await rider.recentPlaces()).first.landmark, dropoff.landmark);

      final place = await rider.addPlace(kind: 'other', label: 'اختبار', place: dropoff);
      expect((await rider.places()).any((p) => p.id == place.id), isTrue);
      await rider.deletePlace(place.id);
      await rider.myRating();
      expect((await rider.cities()), isNotEmpty);
    },
    timeout: const Timeout(Duration(minutes: 3)),
    skip: _base == null ? 'set LIVE_API_URL to run against the local stack' : false,
  );
}
