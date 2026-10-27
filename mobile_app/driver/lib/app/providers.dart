import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/api/api_client.dart';
import '../core/api/api_exception.dart';
import '../core/auth/session_store.dart';
import '../core/location/location_service.dart';
import '../core/realtime/events_socket.dart';
import '../data/driver_api.dart';
import '../data/models.dart';

final sessionStoreProvider = Provider<SessionStore>((ref) => SessionStore());

final apiClientProvider = Provider<ApiClient>((ref) {
  final client = ApiClient(session: ref.watch(sessionStoreProvider));
  ref.listen<Locale>(localeProvider, (_, l) => client.locale = l.languageCode, fireImmediately: true);
  return client;
});

final driverApiProvider = Provider<DriverApi>((ref) => DriverApi(ref.watch(apiClientProvider)));
final locationServiceProvider = Provider<LocationService>((ref) => LocationService());

final localeProvider = StateProvider<Locale>((ref) => const Locale('ar'));

// ---------------------------------------------------------------- authentication

/// Signed-in driver (`/me`), or null. The backend decides the role: only driver-app memberships get here.
class AuthController extends AsyncNotifier<Me?> {
  @override
  Future<Me?> build() async {
    final client = ref.read(apiClientProvider);
    client.onSessionExpired = () => unawaited(_expire());
    final tokens = await ref.read(sessionStoreProvider).read();
    if (tokens == null) return null;
    try {
      return await ref.read(driverApiProvider).me();
    } on ApiException catch (e) {
      if (e.isUnauthorized) {
        await ref.read(sessionStoreProvider).clear();
        return null;
      }
      rethrow; // network etc.: AsyncError with retry
    }
  }

  Future<void> signIn(String phone, String code) async {
    final api = ref.read(driverApiProvider);
    final res = await api.verifyOtp(phone, code);
    await ref.read(sessionStoreProvider).save(Tokens(res['access'] as String, res['refresh'] as String));
    state = AsyncData(await api.me());
  }

  Future<void> refreshMe() async => state = AsyncData(await ref.read(driverApiProvider).me());

  Future<void> signOut() async {
    final store = ref.read(sessionStoreProvider);
    final tokens = await store.read();
    try {
      await ref.read(onlineControllerProvider.notifier).goOffline(silent: true);
      if (tokens != null) await ref.read(driverApiProvider).logout(tokens.refresh);
    } catch (_) {
      // Best effort: the session is cleared locally regardless.
    }
    await ref.read(eventsSocketProvider).stop();
    await store.clear();
    state = const AsyncData(null);
  }

  Future<void> _expire() async {
    await ref.read(eventsSocketProvider).stop();
    await ref.read(sessionStoreProvider).clear();
    state = const AsyncData(null);
  }
}

final authProvider = AsyncNotifierProvider<AuthController, Me?>(AuthController.new);

// ---------------------------------------------------------------- server state (re-read on demand / on hints)

final profileProvider = FutureProvider.autoDispose<DriverProfile>((ref) => ref.watch(driverApiProvider).profile());
final eligibilityProvider = FutureProvider.autoDispose<Eligibility>((ref) => ref.watch(driverApiProvider).eligibility());
final subscriptionProvider = FutureProvider.autoDispose<SubscriptionOverview>((ref) => ref.watch(driverApiProvider).subscription());
final offersProvider = FutureProvider.autoDispose<List<Ride>>((ref) => ref.watch(driverApiProvider).offers());
final ridesProvider = FutureProvider.autoDispose<List<Ride>>((ref) => ref.watch(driverApiProvider).rides());
final rideProvider = FutureProvider.autoDispose.family<Ride, String>((ref, id) => ref.watch(driverApiProvider).ride(id));
final trustProvider = FutureProvider.autoDispose<TrustSnapshot>((ref) => ref.watch(driverApiProvider).trust());
final violationsProvider = FutureProvider.autoDispose<List<Violation>>((ref) => ref.watch(driverApiProvider).violations());

/// Newest-first notifications (the feed pages forward by cursor; read through, bounded).
final notificationsProvider = FutureProvider.autoDispose<List<NotificationItem>>((ref) async {
  final api = ref.watch(driverApiProvider);
  final all = <NotificationItem>[];
  var after = 0;
  for (var i = 0; i < 5; i++) {
    final page = await api.notifications(after: after);
    all.addAll(page.items);
    after = page.nextCursor;
    if (!page.hasMore) break;
  }
  return all.reversed.toList();
});

/// The driver's current assigned / pending-confirmation ride, if any (from their ride list).
final activeRideProvider = FutureProvider.autoDispose<Ride?>((ref) async {
  final rides = await ref.watch(ridesProvider.future);
  for (final r in rides) {
    if (r.isActiveForDriver) return r;
  }
  return null;
});

// ---------------------------------------------------------------- realtime

final eventsSocketProvider = Provider<EventsSocket>((ref) {
  final socket = EventsSocket(session: ref.watch(sessionStoreProvider));
  ref.onDispose(socket.stop);
  return socket;
});

final socketStateProvider = StreamProvider<SocketState>((ref) => ref.watch(eventsSocketProvider).states);

/// Maps hints to the server state they invalidate; screens then re-read the REST API (source of truth).
final realtimeBridgeProvider = Provider<void>((ref) {
  final socket = ref.watch(eventsSocketProvider);
  final sub = socket.hints.listen((hint) {
    ref.invalidate(notificationsProvider);
    final kind = hint.kind;
    if (kind.startsWith('ride.')) {
      ref.invalidate(offersProvider);
      ref.invalidate(ridesProvider);
      final rideId = hint.payload['ride_id'];
      if (rideId is String) ref.invalidate(rideProvider(rideId));
    }
    if (kind.startsWith('driver.') || kind.startsWith('subscription.')) {
      ref.invalidate(profileProvider);
      ref.invalidate(eligibilityProvider);
      ref.invalidate(subscriptionProvider);
    }
  });
  ref.onDispose(sub.cancel);
});

// ---------------------------------------------------------------- availability + location

class OnlineState {
  const OnlineState({
    this.online = false,
    this.busy = false,
    this.locationAccess,
    this.error,
    this.reasons = const [],
    this.lastSentAt,
    this.locationError,
    this.noFix = false,
  });
  final bool online, busy;
  final LocationAccess? locationAccess;
  final ApiException? error;
  final List<String> reasons;

  /// Last time the server accepted a location from this device, and the last send/stream failure (if any).
  final DateTime? lastSentAt;
  final Object? locationError;

  /// No position could be obtained at all (GPS off / no fix yet).
  final bool noFix;

  OnlineState copy({
    bool? online,
    bool? busy,
    LocationAccess? locationAccess,
    ApiException? error,
    List<String>? reasons,
    DateTime? lastSentAt,
    Object? locationError,
    bool clearLocationError = false,
    bool? noFix,
  }) =>
      OnlineState(
        online: online ?? this.online,
        busy: busy ?? this.busy,
        locationAccess: locationAccess,
        error: error,
        reasons: reasons ?? this.reasons,
        lastSentAt: lastSentAt ?? this.lastSentAt,
        locationError: clearLocationError ? null : (locationError ?? this.locationError),
        noFix: noFix ?? this.noFix,
      );
}

/// Going online = permission + a real fix accepted by the server + backend eligibility (`POST driver/availability`,
/// which also refuses without a fresh location). While online, movement updates plus a 30 s heartbeat keep the
/// presence fresh; every failure is kept in state and shown, never swallowed.
class OnlineController extends Notifier<OnlineState> {
  @override
  OnlineState build() {
    final location = ref.read(locationServiceProvider); // providers can't be read while disposing
    ref.onDispose(location.stop);
    return const OnlineState();
  }

  /// Sync with the backend's view (e.g. after an app restart while still online). Does not prompt for
  /// permission; if it is missing the driver sees why location is not updating.
  Future<void> adopt(bool online) async {
    final location = ref.read(locationServiceProvider);
    if (!online) {
      if (state.online) {
        location.stop();
        state = const OnlineState();
      }
      return;
    }
    if (state.online && location.running) return;
    final access = await location.access(request: false);
    state = state.copy(online: true, locationAccess: access);
    if (access == LocationAccess.granted) _startStream();
  }

  Future<void> goOnline() async {
    if (state.busy) return;
    state = state.copy(busy: true);
    final location = ref.read(locationServiceProvider);
    final access = await location.ensureAccess();
    if (access != LocationAccess.granted) {
      state = OnlineState(locationAccess: access);
      return;
    }
    final api = ref.read(driverApiProvider);
    try {
      final fix = await location.current();
      if (fix == null) {
        state = const OnlineState(noFix: true); // never "ready" without a position
        return;
      }
      await api.sendLocation(lat: fix.lat, lng: fix.lng, accuracy: fix.accuracy, heading: fix.heading, speed: fix.speed, deviceTs: fix.deviceTs);
      final sentAt = DateTime.now();
      final result = await api.setAvailability(true);
      state = OnlineState(online: result.isOnline, reasons: result.reasons, lastSentAt: sentAt, locationAccess: access);
      if (result.isOnline) _startStream();
    } on ApiException catch (e) {
      state = OnlineState(error: e, reasons: e.reasons, locationAccess: access);
    } finally {
      ref.invalidate(eligibilityProvider);
      ref.invalidate(offersProvider);
    }
  }

  /// Manual "send my location now" (e.g. after the driver turned GPS back on).
  Future<void> sendNow() async {
    final fix = await ref.read(locationServiceProvider).current();
    if (fix == null) {
      state = state.copy(noFix: true);
      return;
    }
    await _send(fix);
    ref.invalidate(eligibilityProvider);
  }

  Future<void> goOffline({bool silent = false}) async {
    ref.read(locationServiceProvider).stop();
    if (!state.online && silent) return;
    state = state.copy(busy: true);
    try {
      await ref.read(driverApiProvider).setAvailability(false);
      state = const OnlineState();
    } on ApiException catch (e) {
      state = state.copy(busy: false, error: e);
      if (!silent) rethrow;
    } finally {
      ref.invalidate(eligibilityProvider);
    }
  }

  Future<void> _send(Fix fix) async {
    try {
      await ref
          .read(driverApiProvider)
          .sendLocation(lat: fix.lat, lng: fix.lng, accuracy: fix.accuracy, heading: fix.heading, speed: fix.speed, deviceTs: fix.deviceTs);
      state = state.copy(lastSentAt: DateTime.now(), clearLocationError: true, noFix: false);
    } catch (e) {
      state = state.copy(locationError: e);
      rethrow;
    }
  }

  void _startStream() {
    ref.read(locationServiceProvider).start(
          onFix: _send,
          onError: (e) => state = state.copy(locationError: e, noFix: e is StateError),
        );
  }
}

final onlineControllerProvider = NotifierProvider<OnlineController, OnlineState>(OnlineController.new);
