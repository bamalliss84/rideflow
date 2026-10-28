/// Typed models for the driver-facing RideFlow API (packages/contracts/openapi.yaml).
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

class LatLng {
  const LatLng(this.lat, this.lng);
  final double lat;
  final double lng;
  static LatLng? fromJson(Object? v) {
    final m = _map(v);
    final lat = _double(m['lat']), lng = _double(m['lng']);
    return lat == null || lng == null ? null : LatLng(lat, lng);
  }
}

class Me {
  Me(this.json);
  final Json json;
  String get userId => _str(_map(json['user'])['id']);
  String get phone => _str(_map(json['user'])['phone']);
  String get fullName => _str(_map(json['user'])['full_name']);
  String? get tenantName => _map(json['tenant'])['tenant_name'] as String?;
  List<String> get roles => (_map(json['tenant'])['roles'] as List? ?? []).map((e) => e.toString()).toList();
  String? get driverProfileId => json['driver_profile_id'] as String?;
  String get currency => _str(json['currency']);
  int get minorUnits => _int(json['currency_minor_units']) ?? 2;
  String get timeZone => _str(json['time_zone']);
}

class Vehicle {
  Vehicle(Json j)
      : id = _str(j['id']),
        plate = _str(j['plate_number']),
        make = _str(j['make']),
        model = _str(j['model']),
        color = _str(j['color']),
        year = _int(j['year']),
        status = _str(j['status']),
        reviewNote = _str(j['review_note']);
  final String id, plate, make, model, color, status, reviewNote;
  final int? year;
}

class DriverDocument {
  DriverDocument(Json j)
      : id = _str(j['id']),
        docType = _str(j['doc_type']),
        number = _str(j['number']),
        expiresAt = _str(j['expires_at']),
        vehicleId = j['vehicle'] as String?,
        status = _str(j['status']),
        reviewNote = _str(j['review_note']);
  final String id, docType, number, expiresAt, status, reviewNote;
  final String? vehicleId;
}

class DriverProfile {
  DriverProfile(Json j)
      : id = _str(j['id']),
        fullName = _str(j['full_name']),
        phone = _str(j['phone']),
        status = _str(j['status']),
        isOnline = j['is_online'] == true,
        reviewNote = _str(j['review_note']),
        submittedAt = _date(j['submitted_at']),
        reviewedAt = _date(j['reviewed_at']),
        vehicles = _list(j['vehicles']).map(Vehicle.new).toList(),
        documents = _list(j['documents']).map(DriverDocument.new).toList();
  final String id, fullName, phone, status, reviewNote;
  final bool isOnline;
  final DateTime? submittedAt, reviewedAt;
  final List<Vehicle> vehicles;
  final List<DriverDocument> documents;

  bool get canEditApplication => status == 'pending_documents' || status == 'rejected' || status == 'draft';
}

class Eligibility {
  Eligibility(Json j)
      : eligible = j['eligible'] == true,
        reasons = (j['reasons'] as List? ?? []).map((e) => e.toString()).toList(),
        subscriptionActive = j['subscription_active'] == true,
        status = _str(j['status']),
        isOnline = j['is_online'] == true,
        hasLocation = _map(j['presence'])['has_location'] == true,
        locationFresh = _map(j['presence'])['fresh'] == true,
        locationServerTs = _date(_map(j['presence'])['server_ts']),
        staleAfterSeconds = _int(_map(j['presence'])['stale_after_seconds']) ?? 120;
  final bool eligible, subscriptionActive, isOnline, hasLocation, locationFresh;
  final List<String> reasons;
  final String status;
  final DateTime? locationServerTs;
  final int staleAfterSeconds;

  /// Server truth: online AND a fresh position (the same rule dispatch uses).
  bool get ready => isOnline && locationFresh;
}

class Plan {
  Plan(Json j)
      : id = _str(j['id']),
        code = _str(j['code']),
        name = _str(j['name']),
        priceMinor = _int(j['price_minor']) ?? 0,
        durationDays = _int(j['duration_days']) ?? 0,
        isTrial = j['is_trial'] == true;
  final String id, code, name;
  final int priceMinor, durationDays;
  final bool isTrial;
}

class DepositAccount {
  DepositAccount(Json j)
      : id = _str(j['id']),
        bankName = _str(j['bank_name']),
        accountName = _str(j['account_name']),
        accountNumber = _str(j['account_number']),
        instructions = _str(j['instructions']);
  final String id, bankName, accountName, accountNumber, instructions;
}

class DepositClaim {
  DepositClaim(Json j)
      : id = _str(j['id']),
        reference = _str(j['reference']),
        amountMinor = _int(j['amount_minor']) ?? 0,
        currency = _str(j['currency']),
        status = _str(j['status']),
        depositedOn = _str(j['deposited_on']),
        decisionNote = _str(j['decision_note']),
        createdAt = _date(j['created_at']);
  final String id, reference, currency, status, depositedOn, decisionNote;
  final int amountMinor;
  final DateTime? createdAt;
}

class SubscriptionOverview {
  SubscriptionOverview(Json j)
      : entitled = j['entitled'] == true,
        current = j['current'] is Map ? _map(j['current']) : null,
        plans = _list(j['plans']).map(Plan.new).toList(),
        accounts = _list(j['deposit_accounts']).map(DepositAccount.new).toList(),
        recentClaims = _list(j['recent_claims']).map(DepositClaim.new).toList(),
        renewalDiscountPct = _int(j['renewal_discount_pct']) ?? 0;
  final bool entitled;
  final Json? current;
  final List<Plan> plans;
  final List<DepositAccount> accounts;
  final List<DepositClaim> recentClaims;
  final int renewalDiscountPct;

  DateTime? get endsAt => _date(current?['ends_at']);
  String? get currentPlanName => current?['plan_name'] as String?;
  String? get currentSource => current?['source'] as String?;
}

class Bid {
  Bid(Json j)
      : id = _str(j['id']),
        amountMinor = _int(j['amount_minor']) ?? 0,
        etaSeconds = _int(j['eta_seconds']) ?? 0,
        status = _str(j['status']),
        expiresAt = _date(j['expires_at']);
  final String id, status;
  final int amountMinor, etaSeconds;
  final DateTime? expiresAt;
}

class Party {
  Party(Json j)
      : displayName = _str(j['display_name']),
        phone = j['phone'] as String?,
        ratingAvg = _double(_map(j['trust'])['rating_avg']),
        tier = _str(_map(j['trust'])['tier']);
  final String displayName, tier;
  final String? phone;
  final double? ratingAvg;
}

class Ride {
  Ride(this.json)
      : id = _str(json['id']),
        status = _str(json['status']),
        version = _int(json['version']) ?? 0,
        viewerRole = _str(json['viewer_role']),
        allowedActions = (json['allowed_actions'] as List? ?? []).map((e) => e.toString()).toSet(),
        pickup = LatLng.fromJson(json['pickup']),
        dropoff = LatLng.fromJson(json['dropoff']),
        pickupLandmark = _str(json['pickup_landmark']),
        dropoffLandmark = _str(json['dropoff_landmark']),
        riderNote = _str(json['rider_note']),
        currency = _str(json['currency']),
        estimateMin = _int(_map(json['estimate'])['min_minor']),
        estimateMax = _int(_map(json['estimate'])['max_minor']),
        distanceM = _int(_map(json['estimate'])['distance_m']),
        agreedFareMinor = _int(json['agreed_fare_minor']),
        matchDeadline = _date(json['match_deadline']),
        myBid = json['my_bid'] is Map ? Bid(_map(json['my_bid'])) : null,
        rider = json['rider'] is Map ? Party(_map(json['rider'])) : null,
        createdAt = _date(_map(json['timestamps'])['created_at']),
        selectedAt = _date(_map(json['timestamps'])['selected_at']),
        completedAt = _date(_map(json['timestamps'])['completed_at']),
        cancellation = json['cancellation'] is Map ? _map(json['cancellation']) : null,
        cash = json['cash'] is Map ? _map(json['cash']) : null;

  final Json json;
  final String id, status, viewerRole, pickupLandmark, dropoffLandmark, riderNote, currency;
  final int version;
  final Set<String> allowedActions;
  final LatLng? pickup, dropoff;
  final int? estimateMin, estimateMax, distanceM, agreedFareMinor;
  final DateTime? matchDeadline, createdAt, completedAt, selectedAt;
  final Bid? myBid;
  final Party? rider;
  final Json? cancellation, cash;

  static const activeStatuses = {'match_pending', 'assigned', 'en_route', 'arrived', 'in_progress'};
  bool get isActiveForDriver => viewerRole == 'driver' && activeStatuses.contains(status);
  bool get driverCashConfirmed => cash?['driver_confirmed_at'] != null;
  int? get cashAmountMinor => _int(cash?['amount_minor']);
}

class NotificationItem {
  NotificationItem(Json j)
      : cursor = _int(j['cursor']) ?? 0,
        kind = _str(j['kind']),
        payload = _map(j['payload']),
        read = j['read'] == true,
        createdAt = _date(j['created_at']);
  final int cursor;
  final String kind;
  final Json payload;
  final bool read;
  final DateTime? createdAt;
  String? get rideId => payload['ride_id'] as String?;
}

class TrustSnapshot {
  TrustSnapshot(Json j)
      : score = _double(j['score']),
        ratingAvg = _double(j['rating_avg']),
        ratingCount = _int(j['rating_count']) ?? 0,
        completedRides = _int(j['completed_rides']) ?? 0,
        completionRate = _double(j['completion_rate']),
        tier = _str(j['tier']);
  final double? score, ratingAvg, completionRate;
  final int ratingCount, completedRides;
  final String tier;
}

class Violation {
  Violation(Json j)
      : id = _str(j['id']),
        kind = _str(j['kind']),
        status = _str(j['status']),
        createdAt = _date(j['created_at']);
  final String id, kind, status;
  final DateTime? createdAt;
}
