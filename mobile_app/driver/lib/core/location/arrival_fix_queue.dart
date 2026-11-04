import 'dart:convert';

import '../api/api_client.dart' show newActionKey;
import '../api/api_exception.dart';
import '../auth/session_store.dart';
import 'location_service.dart';

/// Rides whose arrival was recorded without a location (D045), and the location that belongs to them.
///
/// Kept on the phone, so neither a weak signal nor a closed app loses it: the location is read as soon as there is one,
/// saved with its true time, and sent when the server can be reached. The app calls [pump] on its regular check.
class ArrivalFixQueue {
  ArrivalFixQueue({required this.kv, required this.location, required this.send, this.onSent});

  static const storageKey = 'rf_arrival_fixes';

  /// A location read later than this says nothing about the arrival, so the phone stops looking.
  static const readFor = Duration(minutes: 3);

  /// A saved location that can't be sent for this long is dropped.
  static const keepFor = Duration(days: 3);

  final SecureKV kv;
  final LocationService location;
  final Future<void> Function(String rideId, Fix fix, String actionKey) send;
  final void Function(String rideId)? onSent;

  bool _pumping = false;

  Future<List<Map<String, dynamic>>> _load() async {
    try {
      final saved = await kv.read(storageKey);
      if (saved == null) return [];
      return (jsonDecode(saved) as List).map((e) => (e as Map).cast<String, dynamic>()).toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> _save(List<Map<String, dynamic>> items) async {
    try {
      items.isEmpty ? await kv.delete(storageKey) : await kv.write(storageKey, jsonEncode(items));
    } catch (_) {}
  }

  /// Remembers that [rideId] still needs its arrival location, then starts looking.
  Future<void> add(String rideId, {DateTime? now}) async {
    final items = await _load();
    if (!items.any((i) => i['ride'] == rideId)) {
      items.add({'ride': rideId, 'since': (now ?? DateTime.now()).toUtc().toIso8601String(), 'key': newActionKey()});
      await _save(items);
    }
    await pump(now: now);
  }

  Future<void> pump({DateTime? now}) async {
    if (_pumping) return;
    _pumping = true;
    try {
      final items = await _load();
      if (items.isEmpty) return;
      final at = now ?? DateTime.now();
      final left = <Map<String, dynamic>>[];
      for (final item in items) {
        if (!await _settle(item, at)) left.add(item);
      }
      await _save(left);
    } finally {
      _pumping = false;
    }
  }

  /// True when the item is finished with: sent, refused by the server or too old.
  Future<bool> _settle(Map<String, dynamic> item, DateTime at) async {
    final age = at.difference(DateTime.parse(item['since'] as String));
    if (age > keepFor) return true;
    if (item['fix'] == null) {
      if (age > readFor) return true;
      final fix = await location.now();
      if (fix == null) return false;
      // Saved with the item: a retry repeats the same body under the same key.
      item['fix'] = {'lat': fix.lat, 'lng': fix.lng, 'accuracy_m': fix.accuracy, 'device_ts': fix.deviceTs.toUtc().toIso8601String()};
    }
    final saved = (item['fix'] as Map).cast<String, dynamic>();
    final fix = Fix(lat: (saved['lat'] as num).toDouble(), lng: (saved['lng'] as num).toDouble(), accuracy: (saved['accuracy_m'] as num).toDouble(), deviceTs: DateTime.parse(saved['device_ts'] as String));
    try {
      await send(item['ride'] as String, fix, item['key'] as String);
      onSent?.call(item['ride'] as String);
      return true;
    } on ApiException catch (e) {
      // No connection, signed out or a server fault can pass. Any other refusal won't change on a retry.
      return !(e.isNetwork || e.status == 401 || e.status == 429 || e.status >= 500);
    } catch (_) {
      return false;
    }
  }
}
