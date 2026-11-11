// Phone notifications: the server is told which phone to notify, once per token, and forgets it on sign-out.
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:rideflow_driver/core/api/api_client.dart';
import 'package:rideflow_driver/core/auth/session_store.dart';
import 'package:rideflow_driver/core/push.dart';

import 'support/fake_backend.dart';

class FakePush implements PushSource {
  FakePush({this.isReady = true, this.value = 'tok-1'});
  final bool isReady;
  String? value;
  int asked = 0;
  final refresh = StreamController<String>.broadcast();

  @override
  Future<bool> ready() async => isReady;
  @override
  Future<void> askPermission() async => asked++;
  @override
  Future<String?> token() async => value;
  @override
  Stream<String> get refreshed => refresh.stream;
}

void main() {
  late FakeBackend backend;
  late ApiClient client;

  setUp(() async {
    backend = FakeBackend({
      'POST me/devices': (_) => (204, null),
      'DELETE me/devices': (_) => (204, null),
    });
    final store = SessionStore(MemoryKV());
    await store.save(const Tokens('a', 'r'));
    client = ApiClient(session: store, dio: backend.dio(), appClientId: 'test');
  });

  List<Object?> calls(String method) => backend.seen.where((s) => s.method == method && s.path == 'me/devices').map((s) => s.body).toList();

  test('asks permission, sends the token once, and a new token again', () async {
    final source = FakePush();
    final push = PushRegistrar(client: client, source: source);
    await push.register();
    await push.register();
    expect(source.asked, 2);
    expect(calls('POST'), [
      {'token': 'tok-1', 'platform': 'android'}
    ]);
    source.refresh.add('tok-2');
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(calls('POST').last, {'token': 'tok-2', 'platform': 'android'});
  });

  test('sign-out forgets this phone', () async {
    final push = PushRegistrar(client: client, source: FakePush());
    await push.register();
    await push.unregister();
    expect(calls('DELETE'), [
      {'token': 'tok-1'}
    ]);
  });

  test('a build without Firebase does nothing and never fails', () async {
    final push = PushRegistrar(client: client, source: FakePush(isReady: false));
    await push.register();
    await push.unregister();
    expect(backend.seen, isEmpty);
  });
}
