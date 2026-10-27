import 'dart:async';

import 'package:geolocator/geolocator.dart';

enum LocationAccess { granted, denied, deniedForever, serviceDisabled }

/// A position sample in the shape the API needs.
class Fix {
  const Fix({required this.lat, required this.lng, required this.accuracy, required this.deviceTs, this.heading, this.speed});
  final double lat, lng, accuracy;
  final DateTime deviceTs;
  final double? heading, speed;

  factory Fix.fromPosition(Position p) =>
      Fix(lat: p.latitude, lng: p.longitude, accuracy: p.accuracy, deviceTs: p.timestamp, heading: p.heading, speed: p.speed);
}

/// Device location for an online driver (foreground only in this phase).
///
/// Two sources feed the sender: the position stream (movement) and a heartbeat that re-sends the latest fix
/// every [heartbeat]. Without the heartbeat a parked driver produced no new samples, its presence went stale
/// after `presence.stale_seconds`, and dispatch silently skipped it.
class LocationService {
  StreamSubscription<Position>? _sub;
  Timer? _heartbeat;
  Fix? last;

  /// Checks (and if [request] asks for) permission. Never requests while the app only syncs state.
  Future<LocationAccess> access({bool request = true}) async {
    if (!await Geolocator.isLocationServiceEnabled()) return LocationAccess.serviceDisabled;
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied && request) permission = await Geolocator.requestPermission();
    return switch (permission) {
      LocationPermission.deniedForever => LocationAccess.deniedForever,
      LocationPermission.denied || LocationPermission.unableToDetermine => LocationAccess.denied,
      _ => LocationAccess.granted,
    };
  }

  Future<LocationAccess> ensureAccess() => access();

  /// A current fix: live reading first, then the platform's last known position. Null = no fix available.
  Future<Fix?> current() async {
    try {
      final p = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, timeLimit: Duration(seconds: 20)));
      return last = Fix.fromPosition(p);
    } catch (_) {
      try {
        final known = await Geolocator.getLastKnownPosition();
        if (known != null) return last = Fix.fromPosition(known);
      } catch (_) {}
      return last;
    }
  }

  /// Starts movement updates plus a heartbeat. [onFix] must return normally or throw; errors are reported
  /// through [onError] (never swallowed) so the UI can show "location not updating".
  void start({
    required Future<void> Function(Fix fix) onFix,
    required void Function(Object error) onError,
    Duration minInterval = const Duration(seconds: 10),
    Duration heartbeat = const Duration(seconds: 30),
  }) {
    stop();
    DateTime? sentAt;
    Future<void> send(Fix fix, {bool force = false}) async {
      final now = DateTime.now();
      if (!force && sentAt != null && now.difference(sentAt!) < minInterval) return;
      sentAt = now;
      try {
        await onFix(fix);
      } catch (e) {
        onError(e);
      }
    }

    _sub = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, distanceFilter: 20),
    ).listen((p) {
      last = Fix.fromPosition(p);
      unawaited(send(last!));
    }, onError: onError);

    _heartbeat = Timer.periodic(heartbeat, (_) async {
      final fix = await current();
      if (fix == null) {
        onError(StateError('no_location_fix'));
        return;
      }
      await send(fix, force: true);
    });
  }

  void stop() {
    _sub?.cancel();
    _sub = null;
    _heartbeat?.cancel();
    _heartbeat = null;
  }

  bool get running => _heartbeat != null;

  Future<bool> openSettings() => Geolocator.openAppSettings();
  Future<bool> openLocationSettings() => Geolocator.openLocationSettings();
}
