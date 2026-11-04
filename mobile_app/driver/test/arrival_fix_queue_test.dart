import 'package:flutter_test/flutter_test.dart';
import 'package:rideflow_driver/core/api/api_exception.dart';
import 'package:rideflow_driver/core/auth/session_store.dart';
import 'package:rideflow_driver/core/location/arrival_fix_queue.dart';
import 'package:rideflow_driver/core/location/location_service.dart';

class _Location extends LocationService {
  Fix? next;
  int reads = 0;
  @override
  Future<Fix?> now() async {
    reads++;
    return next;
  }
}

void main() {
  final at = DateTime.utc(2026, 11, 4, 12);
  final fix = Fix(lat: 14.5, lng: 49.1, accuracy: 8, deviceTs: at);
  late MemoryKV kv;
  late _Location location;
  late List<(String, Fix, String)> sent;
  Object? failWith;

  ArrivalFixQueue queue() => ArrivalFixQueue(
        kv: kv,
        location: location,
        send: (ride, f, key) async {
          if (failWith != null) throw failWith!;
          sent.add((ride, f, key));
        },
      );

  setUp(() {
    kv = MemoryKV();
    location = _Location();
    sent = [];
    failWith = null;
  });

  test('sends the location as soon as there is one, then forgets the ride', () async {
    location.next = fix;
    await queue().add('r1', now: at);
    expect(sent.single.$1, 'r1');
    expect(sent.single.$2.deviceTs, at);
    expect(kv.values[ArrivalFixQueue.storageKey], isNull);
  });

  test('keeps looking while there is no location', () async {
    final q = queue();
    await q.add('r1', now: at);
    expect(sent, isEmpty);
    expect(kv.values[ArrivalFixQueue.storageKey], isNotNull);

    location.next = fix;
    await q.pump(now: at.add(const Duration(seconds: 15)));
    expect(sent.single.$1, 'r1');
  });

  test('stops looking after the reading window', () async {
    final q = queue();
    await q.add('r1', now: at);
    location.next = fix;
    await q.pump(now: at.add(ArrivalFixQueue.readFor + const Duration(seconds: 1)));
    expect(sent, isEmpty);
    expect(kv.values[ArrivalFixQueue.storageKey], isNull);
  });

  test('with no internet the location waits, also across a restart, and is sent unchanged under the same key', () async {
    location.next = fix;
    failWith = ApiException(0, 'network');
    await queue().add('r1', now: at);
    expect(sent, isEmpty);
    expect(kv.values[ArrivalFixQueue.storageKey], isNotNull);

    // A new run of the app, hours later: no new reading is needed.
    failWith = null;
    location = _Location();
    await queue().pump(now: at.add(const Duration(hours: 5)));
    expect(location.reads, 0);
    expect(sent.single.$2.lat, 14.5);
    expect(sent.single.$2.deviceTs, at);
    expect(kv.values[ArrivalFixQueue.storageKey], isNull);
  });

  test('a location that could not be sent for days is dropped', () async {
    location.next = fix;
    failWith = ApiException(0, 'network');
    final q = queue();
    await q.add('r1', now: at);
    failWith = null;
    await q.pump(now: at.add(ArrivalFixQueue.keepFor + const Duration(minutes: 1)));
    expect(sent, isEmpty);
    expect(kv.values[ArrivalFixQueue.storageKey], isNull);
  });

  test('a server fault is retried, a refusal is not', () async {
    location.next = fix;
    failWith = ApiException(503, 'unavailable');
    final q = queue();
    await q.add('r1', now: at);
    expect(kv.values[ArrivalFixQueue.storageKey], isNotNull);

    failWith = ApiException(404, 'not_found');
    await q.pump(now: at);
    expect(kv.values[ArrivalFixQueue.storageKey], isNull);
  });
}
