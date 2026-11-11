import 'dart:convert';

/// Where the operator runs and how the app behaves, read from `GET app/config` (D051). Nothing here is decided in
/// the app: the operator sets it in the portal. The values below the getters are only what the app uses before it
/// has ever reached the server; after that the last copy is kept on the phone and used offline.
class Region {
  const Region({
    this.operatorName = '',
    this.country = '',
    this.currency = '',
    this.currencySymbol = '',
    this.minorUnits = 2,
    this.distanceUnit = 'km',
    this.phoneCode = '',
    this.timeZone = '',
    this.mapLat,
    this.mapLng,
  });

  factory Region.fromJson(Map<String, dynamic> j) {
    final center = j['map_center'] is Map ? (j['map_center'] as Map).cast<String, dynamic>() : null;
    return Region(
      operatorName: '${j['operator_name'] ?? ''}',
      country: '${j['country'] ?? ''}',
      currency: '${j['currency'] ?? ''}',
      currencySymbol: '${j['currency_symbol'] ?? ''}',
      minorUnits: (j['currency_minor_units'] as num?)?.toInt() ?? 2,
      distanceUnit: j['distance_unit'] == 'mi' ? 'mi' : 'km',
      phoneCode: '${j['phone_country_code'] ?? ''}',
      timeZone: '${j['time_zone'] ?? ''}',
      mapLat: (center?['lat'] as num?)?.toDouble(),
      mapLng: (center?['lng'] as num?)?.toDouble(),
    );
  }

  final String operatorName, country, currency, currencySymbol, distanceUnit, phoneCode, timeZone;
  final int minorUnits;
  final double? mapLat, mapLng;

  /// What to show next to an amount in [code]: the operator's symbol for its own currency, the code otherwise.
  String symbolFor(String code) => code == currency && currencySymbol.isNotEmpty ? currencySymbol : code;
}

class AppSettings {
  const AppSettings({this.version = '', this.region = const Region(), this.values = const {}, this.raw = const {}});

  factory AppSettings.fromJson(Map<String, dynamic> j) => AppSettings(
        version: '${j['version'] ?? ''}',
        region: Region.fromJson(j['region'] is Map ? (j['region'] as Map).cast<String, dynamic>() : const {}),
        values: j['settings'] is Map ? (j['settings'] as Map).cast<String, dynamic>() : const {},
        raw: j,
      );

  /// The copy kept on the phone; null when there is none or it can't be read.
  static AppSettings? decode(String? saved) {
    if (saved == null || saved.isEmpty) return null;
    try {
      return AppSettings.fromJson((jsonDecode(saved) as Map).cast<String, dynamic>());
    } catch (_) {
      return null;
    }
  }

  String encode() => jsonEncode(raw);

  final String version;
  final Region region;
  final Map<String, dynamic> values;
  final Map<String, dynamic> raw;

  int number(String key, int before) {
    final v = values[key];
    return v is num ? v.toInt() : before;
  }

  Duration seconds(String key, int before) => Duration(seconds: number(key, before));

  Duration get configCheck => seconds('app.config_check_seconds', 300);
  Duration get driverRequestsRefresh => seconds('app.driver_requests_refresh_seconds', 20);
  Duration get driverReconcile => seconds('app.driver_reconcile_seconds', 15);
  Duration get riderRideRefresh => seconds('app.rider_ride_refresh_seconds', 10);
  Duration get locationMinInterval => seconds('app.location_min_interval_seconds', 10);
  Duration get locationHeartbeat => seconds('app.location_heartbeat_seconds', 30);
  Duration get locationStoppedWarning => seconds('app.location_stopped_warning_seconds', 75);
  Duration get connectionCutGrace => seconds('app.connection_cut_grace_seconds', 15);
  Duration get socketPing => seconds('app.socket_ping_seconds', 25);
  int get mapZoom => number('app.map_zoom', 14);

  List<int> get offerEtaChoices {
    final v = values['app.offer_eta_choices_minutes'];
    final list = v is List ? v.whereType<num>().map((e) => e.toInt()).where((e) => e > 0).toList() : <int>[];
    return list.isEmpty ? const [3, 5, 8, 10, 15] : list;
  }
}

/// The settings in force, for code that runs outside the widget tree (formatting). The provider keeps it current.
AppSettings currentSettings = const AppSettings();
