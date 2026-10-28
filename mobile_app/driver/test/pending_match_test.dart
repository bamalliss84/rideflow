import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rideflow_driver/app/providers.dart';
import 'package:rideflow_driver/core/api/api_client.dart';
import 'package:rideflow_driver/core/auth/session_store.dart';

import 'support/fake_backend.dart';

Map<String, dynamic> ride(String id, String status, String viewer, List<String> actions) =>
    {'id': id, 'status': status, 'version': 3, 'viewer_role': viewer, 'allowed_actions': actions, 'timestamps': {}};

void main() {
  late List<Map<String, dynamic>> pendingList;
  late Map<String, dynamic> single;

  Future<ProviderContainer> setup() async {
    final store = SessionStore(MemoryKV());
    await store.save(const Tokens('a', 'r'));
    final backend = FakeBackend({
      'GET me': (_) => (200, {'user': {'id': 'u'}, 'tenant': {'roles': ['driver']}}),
      'GET rides': (r) => (200, {'results': pendingList}),
      'GET rides/r1': (_) => (200, single),
    });
    final c = ProviderContainer(overrides: [
      sessionStoreProvider.overrideWithValue(store),
      apiClientProvider.overrideWith((ref) => ApiClient(session: store, dio: backend.dio(), appClientId: 'test-driver')),
    ]);
    addTearDown(c.dispose);
    await c.read(authProvider.future);
    return c;
  }

  test('ride.selected hint -> pending confirmation, even before any list refresh', () async {
    pendingList = [];
    single = ride('r1', 'match_pending', 'driver', ['confirm', 'decline']);
    final c = await setup();
    expect(await c.read(pendingMatchProvider.future), isNull);
    await c.read(pendingMatchProvider.notifier).onHint('ride.selected', 'r1');
    expect(c.read(pendingMatchProvider).valueOrNull?.id, 'r1');
  });

  test('restart / missed event: reconciliation alone restores the pending confirmation', () async {
    pendingList = [ride('r1', 'match_pending', 'driver', ['confirm', 'decline'])];
    single = pendingList.first;
    final c = await setup();
    expect((await c.read(pendingMatchProvider.future))?.id, 'r1');
  });

  test('another driver selected (I am only a candidate) is not shown as mine', () async {
    pendingList = [ride('r1', 'match_pending', 'candidate', [])];
    single = pendingList.first;
    final c = await setup();
    expect(await c.read(pendingMatchProvider.future), isNull);
    await c.read(pendingMatchProvider.notifier).onHint('ride.selected', 'r1');
    expect(c.read(pendingMatchProvider).valueOrNull, isNull);
  });

  test('match expired / released -> cleared on the next hint or reconciliation', () async {
    pendingList = [ride('r1', 'match_pending', 'driver', ['confirm', 'decline'])];
    single = pendingList.first;
    final c = await setup();
    expect((await c.read(pendingMatchProvider.future))?.id, 'r1');
    pendingList = [];
    await c.read(pendingMatchProvider.notifier).onHint('ride.match_expired', 'r1');
    expect(c.read(pendingMatchProvider).valueOrNull, isNull);
  });
}
