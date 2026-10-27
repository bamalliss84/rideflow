import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import '../auth/session_store.dart';
import '../config.dart';

/// One realtime hint ({"type": "hint", "cursor", "kind", "payload"}). Hints only say "something changed";
/// screens re-read the authoritative state from the REST API.
class Hint {
  Hint(this.cursor, this.kind, this.payload);
  final int cursor;
  final String kind;
  final Map<String, dynamic> payload;
}

enum SocketState { disconnected, connecting, connected }

/// Per-user event stream (apps/notifications/consumers.py):
/// hello -> resume from the last seen cursor (server replays missed hints) -> live hints; ping/pong keepalive.
/// Duplicates (replay overlapping live delivery) are dropped by cursor. Reconnects with jittered backoff.
class EventsSocket {
  EventsSocket({required this.session, this.connector = _defaultConnector, this.tokenProvider, Uri? endpoint, String? origin})
      : endpoint = endpoint ?? AppConfig.wsEventsUri,
        origin = origin ?? AppConfig.apiOrigin;

  final Uri endpoint;
  final String origin;

  final SessionStore session;
  final Future<WebSocket> Function(Uri uri, Map<String, dynamic> headers) connector;

  /// Returns a currently valid access token (the caller may refresh it first).
  final Future<String?> Function()? tokenProvider;

  final _hints = StreamController<Hint>.broadcast();
  final _state = StreamController<SocketState>.broadcast();
  Stream<Hint> get hints => _hints.stream;
  Stream<SocketState> get states => _state.stream;

  WebSocket? _ws;
  Timer? _ping;
  Timer? _retry;
  int _attempt = 0;
  int _lastCursor = 0;
  bool _running = false;
  final _seen = <int>{};

  static Future<WebSocket> _defaultConnector(Uri uri, Map<String, dynamic> headers) =>
      WebSocket.connect(uri.toString(), headers: headers).timeout(const Duration(seconds: 10));

  Future<void> start() async {
    if (_running) return;
    _running = true;
    _lastCursor = await session.readCursor();
    await _connect();
  }

  Future<void> stop() async {
    _running = false;
    _retry?.cancel();
    _ping?.cancel();
    await _ws?.close();
    _ws = null;
    _emit(SocketState.disconnected);
  }

  /// Foreground return / network change: reconnect now instead of waiting for the backoff.
  void reconnectNow() {
    if (!_running) return;
    if (_ws != null && _ws!.readyState == WebSocket.open) return;
    _retry?.cancel();
    _attempt = 0;
    unawaited(_connect());
  }

  Future<void> _connect() async {
    if (!_running) return;
    final token = tokenProvider != null ? await tokenProvider!() : (await session.read())?.access;
    if (token == null) return;
    _emit(SocketState.connecting);
    try {
      final uri = endpoint.replace(queryParameters: {'token': token});
      final ws = await connector(uri, {'Origin': origin});
      _ws = ws;
      _attempt = 0;
      _emit(SocketState.connected);
      _ping?.cancel();
      _ping = Timer.periodic(const Duration(seconds: 25), (_) => _send({'type': 'ping'}));
      ws.listen(_onMessage, onDone: _onClosed, onError: (_) => _onClosed(), cancelOnError: true);
    } catch (_) {
      _scheduleRetry();
    }
  }

  void _onMessage(dynamic raw) {
    final Map<String, dynamic> msg;
    try {
      msg = (jsonDecode(raw as String) as Map).cast<String, dynamic>();
    } catch (_) {
      return;
    }
    switch (msg['type']) {
      case 'hello':
        _send({'type': 'resume', 'cursor': _lastCursor});
      case 'hint':
        final cursor = (msg['cursor'] as num?)?.toInt() ?? 0;
        if (cursor <= 0 || _seen.contains(cursor)) return; // replay + live overlap
        _seen.add(cursor);
        if (_seen.length > 500) _seen.remove(_seen.reduce(min));
        if (cursor > _lastCursor) {
          _lastCursor = cursor;
          unawaited(session.saveCursor(cursor));
        }
        _hints.add(Hint(cursor, '${msg['kind']}', ((msg['payload'] as Map?) ?? {}).cast<String, dynamic>()));
    }
  }

  void _onClosed() {
    _ping?.cancel();
    _ws = null;
    _emit(SocketState.disconnected);
    _scheduleRetry();
  }

  void _scheduleRetry() {
    if (!_running) return;
    _retry?.cancel();
    final seconds = min(60, pow(2, _attempt).toInt()) + Random().nextInt(3);
    _attempt = min(_attempt + 1, 6);
    _retry = Timer(Duration(seconds: seconds), () => unawaited(_connect()));
  }

  void _send(Map<String, dynamic> msg) {
    final ws = _ws;
    if (ws != null && ws.readyState == WebSocket.open) ws.add(jsonEncode(msg));
  }

  void _emit(SocketState s) {
    if (!_state.isClosed) _state.add(s);
  }

  /// Visible for tests: feed a raw server message.
  void debugReceive(String raw) => _onMessage(raw);
  int get lastCursor => _lastCursor;
}
