import '../core/api/api_client.dart';
import 'models.dart';

Json _json(Object? body) => (body as Map).cast<String, dynamic>();

/// Every rider-side call the app makes. Endpoints and payloads mirror packages/contracts/openapi.yaml;
/// the backend enforces permissions and the ride state machine.
class RiderApi {
  RiderApi(this.client);
  final ApiClient client;

  // ---- auth and account
  Future<void> requestOtp(String phone) => client.post('auth/otp/request', data: {'phone': phone}, auth: false);
  Future<Json> verifyOtp(String phone, String code, {String fullName = ''}) async =>
      _json(await client.post('auth/otp/verify', data: {'phone': phone, 'code': code, if (fullName.isNotEmpty) 'full_name': fullName}, auth: false));
  Future<void> logout(String refresh) => client.post('auth/logout', data: {'refresh': refresh});
  Future<Me> me() async => Me(_json(await client.get('me')));
  Future<Me> updateName(String fullName) async => Me(_json(await client.patch('me', data: {'full_name': fullName})));
  Future<double?> myRating() async {
    final trust = _json(await client.get('me/trust'));
    return trust['rating_provisional'] == true ? null : (trust['rating_avg'] as num?)?.toDouble();
  }

  Future<void> deleteAccount(String code) => client.post('me/delete-account', data: {'code': code});

  // ---- places
  Future<List<City>> cities() async => results(await client.get('cities')).map(City.new).toList();
  Future<List<SavedPlace>> places() async => results(await client.get('me/places')).map(SavedPlace.new).toList();
  Future<SavedPlace> addPlace({required String kind, required String label, required Place place}) async =>
      SavedPlace(_json(await client.post('me/places', data: {'kind': kind, 'label': label, 'landmark': place.landmark, 'point': place.point.toJson()})));
  Future<void> deletePlace(String id) => client.delete('me/places/$id');
  Future<List<Place>> recentPlaces() async => results(await client.get('me/recent-places')).map((j) {
        return Place('${j['landmark']}', Point.fromJson(j['point']) ?? const Point(0, 0));
      }).toList();

  // ---- requesting
  Future<Estimate> estimate(Point pickup, Point dropoff) async =>
      Estimate(_json(await client.post('fare-estimate', data: {'pickup': pickup.toJson(), 'dropoff': dropoff.toJson()})));
  Future<Ride> createRide(RideDraft draft, {String? actionKey}) async => Ride(_json(await client.post(
        'rides',
        actionKey: actionKey,
        data: {
          'pickup': draft.pickup.point.toJson(),
          'pickup_landmark': draft.pickup.landmark,
          'dropoff': draft.dropoff.point.toJson(),
          'dropoff_landmark': draft.dropoff.landmark,
          'pickup_note': draft.pickupNote,
          'dropoff_note': draft.dropoffNote,
          'require_start_code': draft.requireCode,
          if (draft.priceMinor != null) 'rider_price_minor': draft.priceMinor,
        },
      )));

  // ---- the ride
  Future<List<Ride>> rides() async => results(await client.get('rides', query: {'page_size': 50})).map(Ride.new).toList();
  Future<Ride> ride(String id) async => Ride(_json(await client.get('rides/$id')));
  Future<List<Offer>> offers(String id) async => results(await client.get('rides/$id/bids')).map(Offer.new).toList();
  Future<Ride> select(Ride ride, String bidId, {String? actionKey}) async =>
      Ride(_json(await client.post('rides/${ride.id}/select', actionKey: actionKey, data: {'bid_id': bidId, 'expected_version': ride.version})));
  Future<void> dispatchNextWave(String id) => client.post('rides/$id/dispatch', actionKey: newActionKey(), data: {});
  Future<Ride> raisePrice(Ride ride, int amountMinor) async =>
      Ride(_json(await client.post('rides/${ride.id}/raise-price', data: {'amount_minor': amountMinor, 'expected_version': ride.version})));
  Future<Ride> cancel(Ride ride, {required String code, required String reason}) async =>
      Ride(_json(await client.post('rides/${ride.id}/cancel', data: {'expected_version': ride.version, 'reason_code': code, 'reason': reason})));
  Future<DriverPosition> driverPosition(String id) async => DriverPosition(_json(await client.get('rides/$id/driver-location')));
  Future<String?> share(String id) async => _json(await client.post('rides/$id/share'))['url'] as String?;
  Future<void> stopSharing(String id) => client.delete('rides/$id/share');
  Future<void> emergency(String id, Point? location) => client.post('rides/$id/emergency', data: {if (location != null) 'location': location.toJson()});
  Future<Ride> confirmCash(String id, {String? actionKey}) async => Ride(_json(await client.post('rides/$id/cash-confirm', actionKey: actionKey)));
  Future<void> rate(String id, int stars, {List<String> tags = const [], String comment = '', String? actionKey}) =>
      client.post('rides/$id/rating', actionKey: actionKey, data: {'stars': stars, if (tags.isNotEmpty) 'tags': tags, if (comment.isNotEmpty) 'comment': comment});
  Future<void> report(String id, String description) => client.post('rides/$id/disputes', data: {'category': 'other', 'description': description});
}
