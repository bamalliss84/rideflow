import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';

/// Recorded request as the fake server saw it.
class Seen {
  Seen(this.method, this.path, this.headers, this.body);
  final String method, path;
  final Map<String, dynamic> headers;
  final Object? body;
}

typedef Handler = (int, Object?) Function(Seen request);

/// In-process HTTP adapter for Dio: routes "METHOD path" to handlers, records every request.
class FakeBackend implements HttpClientAdapter {
  FakeBackend(this.routes, {this.latency = const {}});
  final Map<String, Handler> routes;

  /// Per-route response delay ("METHOD path"), to reproduce reads still in flight (real network timing).
  final Map<String, Duration> latency;
  final List<Seen> seen = [];

  Dio dio() => Dio(BaseOptions(baseUrl: 'http://fake/api/v1/', validateStatus: (_) => true))..httpClientAdapter = this;

  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    final path = options.uri.path.replaceFirst('/api/v1/', '');
    Object? body = options.data;
    if (body is String && body.isNotEmpty) body = jsonDecode(body);
    final req = Seen(options.method, path, Map.of(options.headers), body);
    seen.add(req);
    final delay = latency['${options.method} $path'];
    if (delay != null) await Future<void>.delayed(delay);
    final handler = routes['${options.method} $path'];
    final (status, payload) = handler == null ? (404, {'code': 'not_found'}) : handler(req);
    return ResponseBody.fromString(jsonEncode(payload), status, headers: {
      Headers.contentTypeHeader: ['application/json'],
    });
  }

  @override
  void close({bool force = false}) {}
}
