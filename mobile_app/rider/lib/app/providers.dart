import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/api/api_client.dart';
import '../core/api/api_exception.dart';
import '../core/auth/session_store.dart';
import '../core/external_apps.dart';
import '../core/location/location_service.dart';
import '../core/realtime/events_socket.dart';
import '../data/models.dart';
import '../data/place_search.dart';
import '../data/rider_api.dart';
import '../design/tokens.dart';

final sessionStoreProvider = Provider<SessionStore>((ref) => SessionStore());
final prefsProvider = Provider<SecureKV>((ref) => const KeystoreKV());

final apiClientProvider = Provider<ApiClient>((ref) {
  final client = ApiClient(session: ref.watch(sessionStoreProvider));
  ref.listen<Locale>(localeProvider, (_, l) => client.locale = l.languageCode, fireImmediately: true);
  return client;
});

final riderApiProvider = Provider<RiderApi>((ref) => RiderApi(ref.watch(apiClientProvider)));

/// What the rider is told about: offers and the trip. Hints the app acts on alone (search widened, an offer withdrawn) stay out.
final notificationsProvider = FutureProvider.autoDispose<List<NotificationItem>>((ref) async {
  final items = await ref.watch(riderApiProvider).notifications();
  return items.where((n) => notificationKinds.contains(n.kind)).toList();
});

const notificationKinds = {
  'ride.bid_created', 'ride.assigned', 'ride.match_released', 'ride.en_route', 'ride.driver_arrived', 'ride.driver_waiting',
  'ride.started', 'ride.completed', 'ride.cancelled', 'ride.expired', 'ride.no_show_recorded',
};

/// A driver's photo, by its address. Kept once read, and tried again if reading it failed.
final photoBytesProvider = FutureProvider.autoDispose.family<Uint8List, String>((ref, path) async {
  final bytes = await ref.read(apiClientProvider).bytes(path);
  ref.keepAlive();
  return bytes;
});
final locationServiceProvider = Provider<LocationService>((ref) => LocationService());
final externalAppsProvider = Provider<ExternalApps>((ref) => const ExternalApps());
final localeProvider = StateProvider<Locale>((ref) => const Locale('ar'));

// ---------------------------------------------------------------- device preferences

/// A choice kept on this phone only. A store that can't be read just means the default.
class DevicePref<T> extends Notifier<T> {
  DevicePref(this.key, this.fallback, this.decode, this.encode);
  final String key;
  final T fallback;
  final T? Function(String) decode;
  final String Function(T) encode;

  @override
  T build() {
    unawaited(_load());
    return fallback;
  }

  Future<void> _load() async {
    try {
      final saved = await ref.read(prefsProvider).read(key);
      final value = saved == null ? null : decode(saved);
      if (value != null) state = value;
    } catch (_) {}
  }

  Future<void> set(T value) async {
    state = value;
    try {
      await ref.read(prefsProvider).write(key, encode(value));
    } catch (_) {}
  }
}

final fontProvider = NotifierProvider<DevicePref<String>, String>(
  () => DevicePref<String>('rf_font', RfFonts.preferred, (s) => RfFonts.available.contains(s) ? s : null, (s) => s),
);
/// Which destination screen to show while the owner compares the two designs (D041): 1 or 3.
final destinationModelProvider = NotifierProvider<DevicePref<int>, int>(() => DevicePref<int>('rf_destination_model', 1, (s) => s == '3' ? 3 : 1, (v) => '$v'));
const appearanceKey = 'rf_appearance';
RfAppearance? decodeAppearance(String? s) => switch (s) { 'day' => RfAppearance.day, 'night' => RfAppearance.night, _ => null };
/// Day or night (D042). main() has already applied the saved choice, so that is the starting value.
final appearanceProvider = NotifierProvider<DevicePref<RfAppearance>, RfAppearance>(() => DevicePref<RfAppearance>(appearanceKey, RfColors.appearance, decodeAppearance, (a) => a.name));
const layoutKey = 'rf_layout_model';
/// Which layout model the screens use (D044). main() has already applied the saved choice.
final layoutProvider = NotifierProvider<DevicePref<RfLayoutModel>, RfLayoutModel>(() => DevicePref<RfLayoutModel>(layoutKey, RfLayout.model, RfLayout.decode, (m) => m.name));
final alwaysCodeProvider = NotifierProvider<DevicePref<bool>, bool>(() => DevicePref<bool>('rf_always_code', false, (s) => s == '1', (b) => b ? '1' : '0'));

// ---------------------------------------------------------------- authentication

class AuthController extends AsyncNotifier<Me?> {
  @override
  Future<Me?> build() async {
    final client = ref.read(apiClientProvider);
    client.onSessionExpired = () => unawaited(_clear());
    final tokens = await ref.read(sessionStoreProvider).read();
    if (tokens == null) return null;
    try {
      return await ref.read(riderApiProvider).me();
    } on ApiException catch (e) {
      if (e.isUnauthorized) {
        await ref.read(sessionStoreProvider).clear();
        return null;
      }
      rethrow; // network etc.: AsyncError with retry
    }
  }

  Future<void> signIn(String phone, String code, {String fullName = ''}) async {
    final api = ref.read(riderApiProvider);
    final res = await api.verifyOtp(phone, code, fullName: fullName);
    await ref.read(sessionStoreProvider).save(Tokens(res['access'] as String, res['refresh'] as String));
    state = AsyncData(await api.me());
  }

  Future<void> rename(String name) async => state = AsyncData(await ref.read(riderApiProvider).updateName(name));

  Future<void> signOut() async {
    final tokens = await ref.read(sessionStoreProvider).read();
    try {
      if (tokens != null) await ref.read(riderApiProvider).logout(tokens.refresh);
    } catch (_) {
      // Best effort: the session is cleared locally regardless.
    }
    await _clear();
  }

  /// The account no longer exists on the server: only the local session is left to clear.
  Future<void> afterAccountDeleted() => _clear();

  Future<void> _clear() async {
    await ref.read(eventsSocketProvider).stop();
    await ref.read(sessionStoreProvider).clear();
    state = const AsyncData(null);
  }
}

final authProvider = AsyncNotifierProvider<AuthController, Me?>(AuthController.new);

// ---------------------------------------------------------------- server state (re-read, never assumed)

final ridesProvider = FutureProvider.autoDispose<List<Ride>>((ref) => ref.watch(riderApiProvider).rides());
final activeRideProvider = FutureProvider.autoDispose<Ride?>((ref) async {
  for (final ride in await ref.watch(ridesProvider.future)) {
    if (ride.isActive) return ride;
  }
  return null;
});
final rideProvider = FutureProvider.autoDispose.family<Ride, String>((ref, id) => ref.watch(riderApiProvider).ride(id));
final offersProvider = FutureProvider.autoDispose.family<List<Offer>, String>((ref, id) => ref.watch(riderApiProvider).offers(id));
final placesProvider = FutureProvider.autoDispose<List<SavedPlace>>((ref) => ref.watch(riderApiProvider).places());
final recentPlacesProvider = FutureProvider.autoDispose<List<Place>>((ref) => ref.watch(riderApiProvider).recentPlaces());
final citiesProvider = FutureProvider<List<City>>((ref) => ref.watch(riderApiProvider).cities());
final myRatingProvider = FutureProvider.autoDispose<double?>((ref) => ref.watch(riderApiProvider).myRating());

final placeSearchProvider = Provider<PlaceSearch>((ref) => PhotonPlaceSearch());

/// The device's position, or null when it can't be read: every screen also works by picking on the map.
final myLocationProvider = FutureProvider.autoDispose<Point?>((ref) async {
  final service = ref.watch(locationServiceProvider);
  if (await service.access() != LocationAccess.granted) return null;
  final fix = await service.current();
  return fix == null ? null : Point(fix.lat, fix.lng);
});

/// The last place the device's position was named, so the same spot shows its name without asking the server again.
final namedSpotProvider = StateProvider<(Point, String)?>((ref) => null);

/// Null when no position is available; a failed read isn't an error for the rider, the map just waits.
final driverPositionProvider = FutureProvider.autoDispose.family<DriverPosition?, String>((ref, id) async {
  try {
    return await ref.watch(riderApiProvider).driverPosition(id);
  } on ApiException {
    return null;
  }
});

final estimateProvider = FutureProvider.autoDispose.family<Estimate, RideDraft>((ref, d) => ref.watch(riderApiProvider).estimate(d.pickup.point, d.dropoff.point));

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
    if (!hint.kind.startsWith('ride.')) return;
    ref.invalidate(ridesProvider);
    final id = hint.payload['ride_id'];
    if (id is String) {
      ref.invalidate(rideProvider(id));
      ref.invalidate(offersProvider(id));
    }
  });
  ref.onDispose(sub.cancel);
});

/// The operator's waiting times, for the "how it works" page (D049).
final waitTimesProvider = FutureProvider.autoDispose<Map<String, int>>((ref) async {
  final body = (await ref.watch(apiClientProvider).get('wait-times')) as Map;
  return {for (final e in body.entries) e.key as String: (e.value as num).toInt()};
});
