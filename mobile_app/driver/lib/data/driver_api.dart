import 'dart:typed_data';

import 'package:dio/dio.dart';

import '../core/api/api_client.dart';
import 'models.dart';

/// Every driver-side call the app makes. Endpoints and payloads mirror packages/contracts/openapi.yaml;
/// the backend enforces eligibility, permissions and the ride state machine.
class DriverApi {
  DriverApi(this.client);
  final ApiClient client;

  // ---- auth
  Future<Json> appContext() async => (await client.get('auth/app-context')) as Json;
  Future<Json> requestOtp(String phone) async =>
      ((await client.post('auth/otp/request', data: {'phone': phone}, auth: false)) as Map).cast<String, dynamic>();
  Future<Json> verifyOtp(String phone, String code) async =>
      ((await client.post('auth/otp/verify', data: {'phone': phone, 'code': code}, auth: false)) as Map).cast<String, dynamic>();
  Future<void> logout(String refresh) => client.post('auth/logout', data: {'refresh': refresh});
  Future<Me> me() async => Me(((await client.get('me')) as Map).cast<String, dynamic>());
  Future<Me> updateName(String fullName) async =>
      Me(((await client.patch('me', data: {'full_name': fullName})) as Map).cast<String, dynamic>());

  // ---- onboarding
  Future<DriverProfile> profile() async => DriverProfile(((await client.get('driver/profile')) as Map).cast<String, dynamic>());
  Future<Eligibility> eligibility() async => Eligibility(((await client.get('driver/eligibility')) as Map).cast<String, dynamic>());
  Future<Vehicle> addVehicle({required String plate, required String make, required String model, required String color, int? year, String? actionKey}) async =>
      Vehicle(((await client.post('driver/vehicles',
              data: {'plate_number': plate, 'make': make, 'model': model, 'color': color, if (year != null) 'year': year},
              actionKey: actionKey)) as Map)
          .cast<String, dynamic>());
  Future<DriverDocument> uploadDocument({
    required String docType,
    required String number,
    required String expiresAt,
    required Uint8List bytes,
    required String filename,
    String? vehicleId,
    String? actionKey,
  }) async =>
      DriverDocument(((await client.upload(
                  'driver/documents',
                  {
                    'doc_type': docType,
                    'number': number,
                    'expires_at': expiresAt,
                    if (vehicleId != null) 'vehicle_id': vehicleId,
                    'file': MultipartFile.fromBytes(bytes, filename: filename),
                  },
                  actionKey: actionKey)) as Map)
          .cast<String, dynamic>());
  Future<DriverProfile> submit({String? actionKey}) async =>
      DriverProfile(((await client.post('driver/submit', actionKey: actionKey)) as Map).cast<String, dynamic>());

  // ---- subscription
  Future<SubscriptionOverview> subscription() async =>
      SubscriptionOverview(((await client.get('driver/subscription')) as Map).cast<String, dynamic>());
  Future<void> startTrial({String? actionKey}) => client.post('driver/subscription/trial', actionKey: actionKey);
  Future<DepositClaim> submitDeposit({
    required String planId,
    required String accountId,
    required int amountMinor,
    required String reference,
    required String depositedOn,
    required Uint8List receipt,
    required String filename,
    String? actionKey,
  }) async =>
      DepositClaim(((await client.upload(
                  'driver/deposit-claims',
                  {
                    'plan_id': planId,
                    'deposit_account_id': accountId,
                    'amount_minor': '$amountMinor',
                    'reference': reference,
                    'deposited_on': depositedOn,
                    'receipt': MultipartFile.fromBytes(receipt, filename: filename),
                  },
                  actionKey: actionKey)) as Map)
          .cast<String, dynamic>());
  Future<List<DepositClaim>> claims() async => results(await client.get('driver/deposit-claims')).map(DepositClaim.new).toList();

  // ---- availability & location
  Future<Eligibility> setAvailability(bool online) async =>
      Eligibility(((await client.post('driver/availability', data: {'online': online})) as Map).cast<String, dynamic>());
  /// Returns whether the server applied the sample (false = older than the stored one).
  Future<bool> sendLocation({required double lat, required double lng, required double accuracy, double? heading, double? speed, DateTime? deviceTs}) async =>
      ((await client.post('driver/location', data: {
        'lat': lat,
        'lng': lng,
        'accuracy_m': accuracy,
        if (heading != null && heading >= 0) 'heading': heading,
        if (speed != null && speed >= 0) 'speed_mps': speed,
        if (deviceTs != null) 'device_ts': deviceTs.toUtc().toIso8601String(),
      })) as Map)['applied'] ==
      true;

  // ---- rides
  Future<List<Ride>> offers() async => results(await client.get('driver/ride-offers')).map(Ride.new).toList();
  Future<List<Ride>> rides({int page = 1}) async =>
      results(await client.get('rides', query: {'page': page, 'page_size': 50})).map(Ride.new).toList();
  Future<Ride> ride(String id) async => Ride(((await client.get('rides/$id')) as Map).cast<String, dynamic>());
  Future<Bid> placeBid(String rideId, {required int amountMinor, required int etaSeconds, required String actionKey}) async =>
      Bid(((await client.post('rides/$rideId/bids', data: {'amount_minor': amountMinor, 'eta_seconds': etaSeconds}, actionKey: actionKey)) as Map)
          .cast<String, dynamic>());
  Future<void> withdrawBid(String rideId, String bidId, {String? actionKey}) =>
      client.post('rides/$rideId/bids/$bidId/withdraw', actionKey: actionKey);

  /// Driver transitions of the backend state machine (apps/rides/state_machine.py). `expected_version`
  /// gives optimistic concurrency; the action key makes a retried tap idempotent.
  Future<Ride> transition(Ride ride, String action, {required String actionKey, Json extra = const {}}) async {
    final path = switch (action) {
      'confirm' => 'confirm',
      'decline' => 'decline',
      'en_route' => 'en-route',
      'arrive' => 'arrive',
      'start' => 'start',
      'complete' => 'complete',
      'driver_cancel' => 'cancel',
      'no_show' => 'no-show',
      _ => throw ArgumentError('unsupported driver action $action'),
    };
    final body = {'expected_version': ride.version, ...extra};
    return Ride(((await client.post('rides/${ride.id}/$path', data: body, actionKey: actionKey)) as Map).cast<String, dynamic>());
  }

  Future<void> contactAttempt(String rideId, String method) => client.post('rides/$rideId/contact-attempts', data: {'method': method});
  Future<Ride> confirmCash(String rideId, {required String actionKey}) async =>
      Ride(((await client.post('rides/$rideId/cash-confirm', actionKey: actionKey)) as Map).cast<String, dynamic>());
  Future<void> rate(String rideId, int stars, {String comment = '', String? actionKey}) =>
      client.post('rides/$rideId/rating', data: {'stars': stars, if (comment.isNotEmpty) 'comment': comment}, actionKey: actionKey);

  // ---- notifications, trust
  Future<({List<NotificationItem> items, int nextCursor, bool hasMore})> notifications({int after = 0}) async {
    final body = ((await client.get('notifications', query: {'after': after, 'limit': 200})) as Map).cast<String, dynamic>();
    return (
      items: results(body['items']).map(NotificationItem.new).toList(),
      nextCursor: (body['next_cursor'] as num?)?.toInt() ?? after,
      hasMore: body['has_more'] == true,
    );
  }

  Future<void> markRead({int? upTo, int? cursor}) =>
      client.post('notifications/read', data: {if (upTo != null) 'up_to': upTo, if (cursor != null) 'cursor': cursor});
  Future<TrustSnapshot> trust() async => TrustSnapshot(((await client.get('me/trust', query: {'role': 'driver'})) as Map).cast<String, dynamic>());
  Future<Json> rewards() async => ((await client.get('driver/rewards')) as Map).cast<String, dynamic>();
  Future<List<Violation>> violations() async => results(await client.get('me/violations')).map(Violation.new).toList();
}
