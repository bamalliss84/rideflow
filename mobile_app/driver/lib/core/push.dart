// Phone notifications (Firebase Cloud Messaging) for when the app is closed or in the background.
//
// The server sends them (apps/notifications/push.py); the phone shows them by itself while the app is not on screen.
// This side only asks for permission and keeps the server told which phone belongs to the signed-in person. An open app
// still learns everything from the socket and REST, so a missing token never loses anything (ADR-0004).
import 'dart:async';
import 'dart:io' show Platform;

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

import 'api/api_client.dart';

/// Where the phone's push token comes from. Firebase in the app, a fake in tests.
abstract class PushSource {
  /// False when push isn't set up on this build (no Firebase config) or the platform has none.
  Future<bool> ready();
  Future<void> askPermission();
  Future<String?> token();
  Stream<String> get refreshed;
}

class FirebasePushSource implements PushSource {
  bool? _ready;

  @override
  Future<bool> ready() async {
    if (_ready != null) return _ready!;
    try {
      if (!Platform.isAndroid && !Platform.isIOS) return _ready = false;
      if (Firebase.apps.isEmpty) await Firebase.initializeApp();
      return _ready = true;
    } catch (_) {
      return _ready = false; // built without google-services.json, or no Google services on the phone
    }
  }

  @override
  Future<void> askPermission() async {
    // Android 13+ shows nothing (including the driver's "online" notice) until the person allows it.
    await FirebaseMessaging.instance.requestPermission();
  }

  @override
  Future<String?> token() => FirebaseMessaging.instance.getToken();

  @override
  Stream<String> get refreshed => FirebaseMessaging.instance.onTokenRefresh;
}

/// Tells the server which phone to notify for the signed-in person, and forgets it on sign-out.
class PushRegistrar {
  PushRegistrar({required this.client, required this.source});
  final ApiClient client;
  final PushSource source;
  String? _sent;
  StreamSubscription<String>? _refresh;

  /// Never throws: a failure only means no notifications until the next start.
  Future<void> register() async {
    try {
      if (!await source.ready()) return;
      await source.askPermission();
      await _send(await source.token());
      _refresh ??= source.refreshed.listen((t) => unawaited(_send(t).catchError((_) {})));
    } catch (_) {}
  }

  Future<void> _send(String? token) async {
    if (token == null || token.isEmpty || token == _sent) return;
    await client.post('me/devices', data: {'token': token, 'platform': Platform.isIOS ? 'ios' : 'android'});
    _sent = token;
  }

  /// Before signing out, while the session still works: this phone stops getting this person's notifications.
  Future<void> unregister() async {
    await _refresh?.cancel();
    _refresh = null;
    final token = _sent;
    _sent = null;
    if (token == null) return;
    try {
      await client.delete('me/devices', data: {'token': token});
    } catch (_) {}
  }
}
