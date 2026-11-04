/// Typed models for the rider-facing RideFlow API (packages/contracts/openapi.yaml).
/// Parsing is tolerant of nulls; unknown enum values are kept as strings and shown generically.
library;

typedef Json = Map<String, dynamic>;

Json _map(Object? v) => v is Map ? v.cast<String, dynamic>() : <String, dynamic>{};
List<Json> _list(Object? v) => v is List ? v.map(_map).toList() : <Json>[];
DateTime? _date(Object? v) => v is String ? DateTime.tryParse(v)?.toLocal() : null;
int? _int(Object? v) => v is int ? v : (v is num ? v.toInt() : int.tryParse('${v ?? ''}'));
double? _double(Object? v) => v is num ? v.toDouble() : double.tryParse('${v ?? ''}');
String _str(Object? v) => v?.toString() ?? '';

/// Paginated list ({count, results}) or plain list.
List<Json> results(Object? body) => body is Map ? _list(body['results']) : _list(body);

class Point {
  const Point(this.lat, this.lng);
  final double lat, lng;
  static Point? fromJson(Object? v) {
    final m = _map(v);
    final lat = _double(m['lat']), lng = _double(m['lng']);
    return lat == null || lng == null ? null : Point(lat, lng);
  }

  Json toJson() => {'lat': lat, 'lng': lng};
}

/// A stop in the rider's words: addresses here are landmarks, so the wording is part of the data.
class Place {
  const Place(this.landmark, this.point);
  final String landmark;
  final Point point;
}

class SavedPlace {
  SavedPlace(Json j)
      : id = _str(j['id']),
        kind = _str(j['kind']),
        label = _str(j['label']),
        landmark = _str(j['landmark']),
        point = Point.fromJson(j['point']) ?? const Point(0, 0);
  final String id, kind, label, landmark;
  final Point point;
  Place get place => Place(landmark, point);
}

class Me {
  Me(this.json);
  final Json json;
  String get phone => _str(_map(json['user'])['phone']);
  String get fullName => _str(_map(json['user'])['full_name']);
  String get currency => _str(json['currency']);
  int get minorUnits => _int(json['currency_minor_units']) ?? 2;
}

class City {
  City(Json j)
      : name = _str(j['name']),
        center = Point.fromJson(j['center']) ?? const Point(0, 0);
  final String name;
  final Point center;
}

class Estimate {
  Estimate(Json j)
      : distanceM = _int(j['distance_m']) ?? 0,
        minMinor = _int(j['min_minor']) ?? 0,
        maxMinor = _int(j['max_minor']) ?? 0,
        riderMinMinor = _int(j['rider_price_min_minor']) ?? 0,
        currency = _str(j['currency']);
  final int distanceM, minMinor, maxMinor, riderMinMinor;
  final String currency;
}

class Vehicle {
  Vehicle(Json j)
      : make = _str(j['make']),
        model = _str(j['model']),
        color = _str(j['color']),
        plate = j['plate_number'] as String?;
  final String make, model, color;
  final String? plate;
  String get name => '$make $model'.trim();
}

class Driver {
  Driver(Json j)
      : name = _str(j['display_name']),
        phone = j['phone'] as String?,
        photoUrl = j['photo_url'] as String?,
        ratingAvg = _double(_map(j['trust'])['rating_avg']),
        ratingProvisional = _map(j['trust'])['rating_provisional'] != false,
        completedRides = _int(_map(j['trust'])['completed_rides']) ?? 0,
        vehicle = j['vehicle'] is Map ? Vehicle(_map(j['vehicle'])) : null;
  final String name;
  final String? phone, photoUrl;
  final double? ratingAvg;
  final bool ratingProvisional;
  final int completedRides;
  final Vehicle? vehicle;
}

class Offer {
  Offer(Json j)
      : id = _str(j['id']),
        amountMinor = _int(j['amount_minor']) ?? 0,
        currency = _str(j['currency']),
        etaSeconds = _int(j['eta_seconds']) ?? 0,
        status = _str(j['status']),
        expiresAt = _date(j['expires_at']),
        createdAt = _date(j['created_at']),
        driver = j['driver'] is Map ? Driver(_map(j['driver'])) : null;
  final String id, currency, status;
  final int amountMinor, etaSeconds;
  final DateTime? expiresAt, createdAt;
  final Driver? driver;
  bool isLive(DateTime now) => status == 'open' && (expiresAt == null || expiresAt!.isAfter(now));
}

class DriverPosition {
  DriverPosition(Json j)
      : point = Point.fromJson(j) ?? const Point(0, 0),
        stale = j['stale'] == true;
  final Point point;
  final bool stale;
}

class Ride {
  Ride(this.json)
      : id = _str(json['id']),
        status = _str(json['status']),
        version = _int(json['version']) ?? 0,
        pickup = Point.fromJson(json['pickup']),
        dropoff = Point.fromJson(json['dropoff']),
        pickupLandmark = _str(json['pickup_landmark']),
        dropoffLandmark = _str(json['dropoff_landmark']),
        pickupNote = _str(json['pickup_note']),
        dropoffNote = _str(json['dropoff_note']),
        currency = _str(json['currency']),
        estimateMin = _int(_map(json['estimate'])['min_minor']),
        estimateMax = _int(_map(json['estimate'])['max_minor']),
        distanceM = _int(_map(json['estimate'])['distance_m']),
        stepMinor = _int(_map(json['estimate'])['bid_step_minor']),
        riderPriceMinor = _int(json['rider_price_minor']),
        myRatingStars = _int(_map(json['my_rating'])['stars']),
        agreedFareMinor = _int(json['agreed_fare_minor']),
        matchDeadline = _date(json['match_deadline']),
        freeCancelUntil = _date(json['free_cancel_until']),
        startCode = json['start_code'] as String?,
        startCodeRequired = json['start_code_required'] == true,
        emergencyPhone = json['emergency_phone'] as String?,
        shareActive = json['share_active'] == true,
        driver = json['driver'] is Map ? Driver(_map(json['driver'])) : null,
        createdAt = _date(_map(json['timestamps'])['created_at']),
        startedAt = _date(_map(json['timestamps'])['started_at']),
        completedAt = _date(_map(json['timestamps'])['completed_at']),
        cancellation = json['cancellation'] is Map ? _map(json['cancellation']) : null,
        cash = json['cash'] is Map ? _map(json['cash']) : null,
        allowedActions = (json['allowed_actions'] as List? ?? []).map((e) => e.toString()).toSet();

  final Json json;
  final String id, status, pickupLandmark, dropoffLandmark, pickupNote, dropoffNote, currency;
  final int version;
  final Point? pickup, dropoff;
  final int? estimateMin, estimateMax, distanceM, stepMinor, riderPriceMinor, myRatingStars, agreedFareMinor;
  final DateTime? matchDeadline, freeCancelUntil, createdAt, startedAt, completedAt;
  final String? startCode, emergencyPhone;
  final bool startCodeRequired, shareActive;
  final Driver? driver;
  final Json? cancellation, cash;
  final Set<String> allowedActions;

  static const activeStatuses = {'requested', 'bidding', 'match_pending', 'assigned', 'en_route', 'arrived', 'in_progress'};
  bool get isActive => activeStatuses.contains(status);
  bool get canCancel => allowedActions.contains('rider_cancel');
  bool get cashConfirmedByMe => cash?['rider_confirmed_at'] != null;
  bool get expiredWithoutOffers => status == 'cancelled' && cancellation?['by_role'] == 'system';
  int? get fareMinor => _int(cash?['amount_minor']) ?? agreedFareMinor;

  /// Short reference for receipts, taken from the id so it needs no new field.
  String get reference => 'RF-${id.replaceAll('-', '').substring(0, id.length >= 8 ? 8 : id.length).toUpperCase()}';
}

/// What the request screen sends.
class RideDraft {
  const RideDraft({required this.pickup, required this.dropoff, this.pickupNote = '', this.dropoffNote = '', this.requireCode = false, this.priceMinor});
  final Place pickup, dropoff;
  final String pickupNote, dropoffNote;
  final bool requireCode;
  final int? priceMinor;
}
