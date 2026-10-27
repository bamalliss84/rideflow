// Live integration test: the app's own API, session and realtime layers against the running local stack.
// Uses the dedicated `e2e-qa` tenant (seed: `manage.py seed_e2e`). Skipped unless LIVE_API_URL is set:
//   $env:LIVE_API_URL="http://127.0.0.1:8010"; flutter test test/live
import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rideflow_driver/core/api/api_client.dart';
import 'package:rideflow_driver/core/api/api_exception.dart';
import 'package:rideflow_driver/core/auth/session_store.dart';
import 'package:rideflow_driver/core/realtime/events_socket.dart';
import 'package:rideflow_driver/data/driver_api.dart';
import 'package:rideflow_driver/features/history/history_screens.dart';

final apiUrl = Platform.environment['LIVE_API_URL'];
final portalUrl = Platform.environment['LIVE_PORTAL_URL'] ?? 'http://127.0.0.1:3000';
const driverApp = 'e2e-qa-driver', riderApp = 'e2e-qa-rider', adminApp = 'e2e-qa-admin';
const reviewerPhone = '+967799000004'; // E2E Reviewer Two (seed_e2e)
const centerLat = 14.70, centerLng = 49.35;

String phone() => '+9677${(1000000 + Random().nextInt(8999999)).toString()}${Random().nextInt(10)}';
Uint8List png() => Uint8List.fromList([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, ...List.filled(64, 0), ...'${DateTime.now().microsecondsSinceEpoch}${Random().nextInt(1 << 30)}'.codeUnits]);

/// Staff session through the admin portal BFF (dev MFA bypass, local only); returns the access cookie.
Future<String> staffToken() async {
  final dio = Dio(BaseOptions(baseUrl: portalUrl, headers: {'Origin': portalUrl}, validateStatus: (_) => true));
  final r1 = await dio.post('/api/auth/otp-request', data: {'workspace': adminApp, 'phone': reviewerPhone});
  expect(r1.statusCode, 202, reason: '${r1.data}');
  final r2 = await dio.post('/api/auth/otp-verify', data: {'workspace': adminApp, 'phone': reviewerPhone, 'code': '000000'});
  expect(r2.statusCode, 200, reason: '${r2.data}');
  final cookie = (r2.headers['set-cookie'] ?? []).firstWhere((c) => c.startsWith('rf_at='));
  return cookie.substring(6, cookie.indexOf(';'));
}

Dio raw(String app, [String? token]) => Dio(BaseOptions(
      baseUrl: '$apiUrl/api/v1/',
      headers: {'X-RideFlow-App': app, if (token != null) 'Authorization': 'Bearer $token'},
      validateStatus: (_) => true,
    ));

Future<String> otpLogin(String app, String number) async {
  final d = raw(app);
  await d.post('auth/otp/request', data: {'phone': number});
  final r = await d.post('auth/otp/verify', data: {'phone': number, 'code': '000000'});
  expect(r.statusCode, 200, reason: '${r.data}');
  return r.data['access'] as String;
}

Future<Response<dynamic>> idem(Dio d, String path, Object data) =>
    d.post(path, data: data, options: Options(headers: {'Idempotency-Key': newActionKey()}));

void main() {
  test('driver lifecycle against the real backend: onboarding, approval, trial, online, bid, confirm, trip, cash, rating, realtime',
      timeout: const Timeout(Duration(minutes: 3)), skip: apiUrl == null ? 'set LIVE_API_URL to run' : false, () async {
    final store = SessionStore(MemoryKV());
    final client = ApiClient(session: store, baseUrl: apiUrl, appClientId: driverApp);
    final api = DriverApi(client);

    // ---- sign-in through the app's API layer
    final driverPhone = phone();
    await api.requestOtp(driverPhone);
    final login = await api.verifyOtp(driverPhone, '000000');
    await store.save(Tokens(login['access'] as String, login['refresh'] as String));
    final me = await api.me();
    expect(me.roles, contains('driver'));
    expect(me.driverProfileId, isNotNull);

    // ---- onboarding
    var profile = await api.profile();
    expect(profile.status, 'pending_documents');
    final vehicle = await api.addVehicle(plate: 'APP ${Random().nextInt(99999)}', make: 'Toyota', model: 'Hilux', color: 'White', year: 2018);
    for (final type in ['national_id', 'driving_license', 'vehicle_registration']) {
      await api.uploadDocument(
          docType: type, number: 'N-$type', expiresAt: '2031-01-01', bytes: png(), filename: '$type.png', vehicleId: type == 'vehicle_registration' ? vehicle.id : null);
    }
    final submitKey = newActionKey();
    profile = await api.submit(actionKey: submitKey);
    expect(profile.status, 'under_review');
    // driver/submit is not idempotency-keyed: a retry is refused by the state guard (nothing applied twice).
    final again = await api.submit(actionKey: submitKey).then<ApiException?>((_) => null, onError: (Object e) => e as ApiException);
    expect(again?.status, 409);
    var eligibility = await api.eligibility();
    expect(eligibility.eligible, isFalse);
    expect(eligibility.reasons, contains('driver_under_review'));

    // ---- operator review (staff API) - the app cannot approve itself
    final reviewer = raw(adminApp, await staffToken());
    for (final doc in (await reviewer.get('admin/driver-documents', queryParameters: {'driver': profile.id})).data['results'] as List) {
      expect((await idem(reviewer, 'admin/driver-documents/${doc['id']}/approve', {'note': ''})).statusCode, 200);
    }
    expect((await idem(reviewer, 'admin/vehicles/${vehicle.id}/approve', {'note': ''})).statusCode, 200);
    expect((await idem(reviewer, 'admin/drivers/${profile.id}/decide', {'decision': 'approve', 'note': ''})).statusCode, 200);

    // ---- subscription gate, then trial
    expect((await api.eligibility()).reasons, contains('subscription_inactive'));
    final refused = await api.setAvailability(true).then<ApiException?>((_) => null, onError: (Object e) => e as ApiException);
    expect(refused?.reasons, contains('subscription_inactive'));
    final overview = await api.subscription();
    expect(overview.entitled, isFalse);
    expect(overview.plans.any((p) => p.isTrial), isTrue);
    await api.startTrial();
    expect((await api.subscription()).entitled, isTrue);

    // ---- online with a location fix
    await api.sendLocation(lat: centerLat, lng: centerLng, accuracy: 8, deviceTs: DateTime.now());
    eligibility = await api.setAvailability(true);
    expect(eligibility.isOnline, isTrue);

    // ---- realtime stream (same client code as the app)
    final socket = EventsSocket(session: store, endpoint: Uri.parse(apiUrl!).replace(scheme: 'ws', path: '/ws/v1/events/'), origin: apiUrl);
    final hints = <String>[];
    final selected = Completer<void>();
    final sub = socket.hints.listen((h) {
      hints.add(h.kind);
      if (h.kind == 'ride.selected' && !selected.isCompleted) selected.complete();
    });
    final connected = socket.states.firstWhere((s) => s == SocketState.connected); // subscribe before start()
    await socket.start();
    await connected.timeout(const Duration(seconds: 10));

    // ---- a rider requests nearby; the offer reaches this driver
    final rider = raw(riderApp, await otpLogin(riderApp, phone()));
    final created = await idem(rider, 'rides', {
      'pickup': {'lat': centerLat, 'lng': centerLng},
      'pickup_landmark': 'Driver app live test',
      'dropoff': {'lat': centerLat + 0.02, 'lng': centerLng + 0.02},
      'dropoff_landmark': 'Destination',
    });
    expect(created.statusCode, 201, reason: '${created.data}');
    final rideId = created.data['id'] as String;
    final offers = await api.offers();
    final offer = offers.firstWhere((r) => r.id == rideId);
    expect(offer.viewerRole, 'candidate');
    expect(offer.allowedActions, {'bid'});
    expect(offer.rider?.phone, isNull); // no contact data before assignment

    final bidKey = newActionKey();
    final bid = await api.placeBid(rideId, amountMinor: 150000, etaSeconds: 300, actionKey: bidKey);
    final replay = await api.placeBid(rideId, amountMinor: 150000, etaSeconds: 300, actionKey: bidKey);
    expect(replay.id, bid.id); // a retried tap never creates a second bid

    // ---- rider selects -> realtime hint -> driver confirms with expected_version
    final snap = (await rider.get('rides/$rideId')).data;
    expect((await idem(rider, 'rides/$rideId/select', {'bid_id': bid.id, 'expected_version': snap['version']})).statusCode, 200);
    await selected.future.timeout(const Duration(seconds: 15));
    var ride = await api.ride(rideId);
    expect(ride.status, 'match_pending');
    expect(ride.allowedActions, containsAll(['confirm', 'decline']));
    final confirmKey = newActionKey();
    ride = await api.transition(ride, 'confirm', actionKey: confirmKey);
    expect(ride.status, 'assigned');
    expect(ride.rider?.phone, isNotNull); // contact only once assigned

    // stale version is refused (optimistic concurrency), not applied twice
    final stale = await api.transition(ride, 'en_route', actionKey: newActionKey()).then((r) => r);
    expect(stale.status, 'en_route');
    final conflict = await api
        .transition(ride, 'arrive', actionKey: newActionKey(), extra: {'lat': centerLat, 'lng': centerLng, 'accuracy_m': 5})
        .then<ApiException?>((_) => null, onError: (Object e) => e as ApiException);
    expect(conflict?.status, 409);

    ride = await api.ride(rideId);
    ride = await api.transition(ride, 'arrive', actionKey: newActionKey(), extra: {'lat': centerLat, 'lng': centerLng, 'accuracy_m': 5});
    expect(ride.status, 'arrived');
    ride = await api.transition(ride, 'start', actionKey: newActionKey());
    ride = await api.transition(ride, 'complete', actionKey: newActionKey());
    expect(ride.status, 'completed');
    expect(ride.agreedFareMinor, 150000);
    expect(ride.driverCashConfirmed, isFalse);
    ride = await api.confirmCash(rideId, actionKey: newActionKey());
    expect(ride.driverCashConfirmed, isTrue);
    await api.rate(rideId, 5);

    // ---- history / earnings from real records; trust; notifications
    final rides = await api.rides();
    expect(summarize(rides, DateTime.now().subtract(const Duration(days: 1))).total, greaterThanOrEqualTo(150000));
    expect((await api.trust()).completedRides, greaterThanOrEqualTo(1));
    final feed = await api.notifications();
    expect(feed.items.any((n) => n.kind == 'ride.selected'), isTrue);
    expect(hints, contains('ride.selected'));

    // ---- offline, logout; the old refresh token is dead
    expect((await api.setAvailability(false)).isOnline, isFalse);
    await socket.stop();
    await sub.cancel();
    final refresh = (await store.read())!.refresh;
    await api.logout(refresh);
    final r = await raw(driverApp).post('auth/token/refresh', data: {'refresh': refresh});
    expect(r.statusCode, 401);
  });
}
