import 'dart:async';
import 'dart:io' show Platform;

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

/// Null when [fix] is too old to count as where the driver is. The server drops a sample no newer than the one it has,
/// and refuses to go online without a recent one, so an old fix would only fail without saying why.
Fix? freshFix(Fix? fix, {DateTime? now, Duration maxAge = const Duration(minutes: 2)}) => fix != null && (now ?? DateTime.now()).difference(fix.deviceTs) < maxAge ? fix : null;

/// Device location for an online driver.
///
/// Two sources feed the sender: the position stream (movement) and a heartbeat that re-sends the latest fix
/// every [heartbeat]. Without the heartbeat a parked driver produced no new samples, its presence went stale
/// after `presence.stale_seconds`, and dispatch silently skipped it.
///
/// On Android the stream runs in a foreground service with an "online" notification. Without it the phone stops giving
/// the app its location as soon as the screen sleeps or another app is opened, and requests stop reaching the driver.
class LocationService {
  StreamSubscription<Position>? _sub;
  Timer? _heartbeat;
  Fix? last;

  /// Title and text of the ongoing notification while online, in the driver's language. Set by the app shell.
  ({String title, String text}) notice = (title: 'RideFlow', text: '');

  Future<void> Function(Fix fix, {bool force})? _send;
  Duration _minInterval = const Duration(seconds: 10);

  LocationSettings _streamSettings() {
    if (!Platform.isAndroid) return const LocationSettings(accuracy: LocationAccuracy.high, distanceFilter: 20);
    return AndroidSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 20,
      foregroundNotificationConfig: ForegroundNotificationConfig(
        notificationTitle: notice.title,
        notificationText: notice.text,
        enableWakeLock: true,
        setOngoing: true,
      ),
    );
  }

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

  /// A current fix: live reading first, then a recent last known position. Null = no fix available.
  Future<Fix?> current() => _read(const Duration(seconds: 20));

  /// A fix for a button the driver just tapped, which shouldn't wait on a new GPS reading. While online the position
  /// stream and the heartbeat keep [last] within 20 m and 30 seconds of the driver, so that is used, with its true time.
  Future<Fix?> now() async => freshFix(last, maxAge: const Duration(seconds: 45)) ?? await _read(const Duration(seconds: 5));

  Future<Fix?> _read(Duration limit) async {
    try {
      final p = await Geolocator.getCurrentPosition(locationSettings: LocationSettings(accuracy: LocationAccuracy.high, timeLimit: limit));
      return last = Fix.fromPosition(p);
    } catch (_) {
      try {
        final known = await Geolocator.getLastKnownPosition();
        if (known != null) return freshFix(last = Fix.fromPosition(known));
      } catch (_) {}
      return freshFix(last);
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
    _minInterval = minInterval;
    DateTime? sentAt;
    Future<void> send(Fix fix, {bool force = false}) async {
      final now = DateTime.now();
      if (!force && sentAt != null && now.difference(sentAt!) < _minInterval) return;
      sentAt = now;
      try {
        await onFix(fix);
      } catch (e) {
        onError(e);
      }
    }

    _send = send;
    _sub = Geolocator.getPositionStream(locationSettings: _streamSettings()).listen((p) {
      last = Fix.fromPosition(p);
      unawaited(send(last!));
    }, onError: onError);
    _startHeartbeat(heartbeat, onError);
  }

  void _startHeartbeat(Duration every, void Function(Object error) onError) {
    _heartbeat?.cancel();
    _heartbeat = Timer.periodic(every, (_) async {
      final fix = await current();
      if (fix == null) {
        onError(StateError('no_location_fix'));
        return;
      }
      await _send?.call(fix, force: true);
    });
  }

  /// New gaps from the operator while online. Keeps the stream (and its foreground service) running: Android refuses to
  /// start the service again while the app is in the background.
  void retime({required Duration minInterval, required Duration heartbeat, required void Function(Object error) onError}) {
    if (!running) return;
    _minInterval = minInterval;
    _startHeartbeat(heartbeat, onError);
  }

  void stop() {
    _sub?.cancel();
    _sub = null;
    _heartbeat?.cancel();
    _heartbeat = null;
    _send = null;
  }

  bool get running => _heartbeat != null;

  Future<bool> openSettings() => Geolocator.openAppSettings();
  Future<bool> openLocationSettings() => Geolocator.openLocationSettings();
}
