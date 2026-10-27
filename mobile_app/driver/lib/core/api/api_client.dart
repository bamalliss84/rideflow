import 'dart:async';

import 'package:dio/dio.dart';
import 'package:uuid/uuid.dart';

import '../auth/session_store.dart';
import '../config.dart';
import 'api_exception.dart';

const _uuid = Uuid();

/// A fresh idempotency key for one logical user action. Reuse the same key when retrying that action, so
/// the server replays the first result instead of applying it twice (duplicate bids, confirmations...).
String newActionKey() => _uuid.v4();

/// Central HTTP client: app-context header, bearer token, single-flight refresh with rotation, uniform errors.
class ApiClient {
  ApiClient({required this.session, Dio? dio, String? baseUrl, String? appClientId, this.onSessionExpired})
      : appClientId = appClientId ?? AppConfig.appClientId,
        dio = dio ??
            Dio(BaseOptions(
              baseUrl: '${baseUrl ?? AppConfig.apiBaseUrl}/api/v1/',
              connectTimeout: const Duration(seconds: 10),
              receiveTimeout: const Duration(seconds: 20),
              sendTimeout: const Duration(seconds: 60),
              validateStatus: (_) => true,
            ));

  final SessionStore session;
  final Dio dio;
  final String appClientId;

  /// Called when the refresh token is rejected: the user must sign in again.
  void Function()? onSessionExpired;
  String locale = 'ar';

  Future<Tokens?>? _refreshing;

  Future<dynamic> get(String path, {Map<String, dynamic>? query}) => _send('GET', path, query: query);

  Future<dynamic> post(String path, {Object? data, String? actionKey, bool auth = true}) =>
      _send('POST', path, data: data, actionKey: actionKey ?? newActionKey(), auth: auth);

  Future<dynamic> patch(String path, {Object? data}) => _send('PATCH', path, data: data);

  Future<dynamic> upload(String path, Map<String, dynamic> fields, {String? actionKey}) =>
      _send('POST', path, data: FormData.fromMap(fields), actionKey: actionKey ?? newActionKey());

  Future<dynamic> _send(String method, String path,
      {Object? data, Map<String, dynamic>? query, String? actionKey, bool auth = true, bool retried = false}) async {
    final tokens = auth ? await session.read() : null;
    final headers = <String, dynamic>{
      'X-RideFlow-App': appClientId,
      'Accept': 'application/json',
      'Accept-Language': locale,
      if (tokens != null) 'Authorization': 'Bearer ${tokens.access}',
      if (actionKey != null) 'Idempotency-Key': actionKey,
    };
    Response<dynamic> res;
    try {
      res = await dio.request<dynamic>(path,
          data: data is FormData && retried ? data.clone() : data,
          queryParameters: query,
          options: Options(method: method, headers: headers));
    } on DioException catch (e) {
      throw ApiException(0, 'network', detail: e.message);
    }
    final status = res.statusCode ?? 0;
    if (status == 401 && auth && tokens != null && !retried) {
      final renewed = await _refreshOnce(tokens);
      if (renewed != null) {
        return _send(method, path, data: data, query: query, actionKey: actionKey, auth: auth, retried: true);
      }
      onSessionExpired?.call();
    }
    if (status >= 200 && status < 300) return res.data;
    throw ApiException.fromResponse(status, res.data);
  }

  /// Refresh tokens rotate and are single-use: concurrent 401s share one refresh request.
  Future<Tokens?> _refreshOnce(Tokens stale) {
    return _refreshing ??= () async {
      try {
        final current = await session.read();
        if (current != null && current.access != stale.access) return current; // already renewed by another call
        final res = await dio.post<dynamic>('auth/token/refresh',
            data: {'refresh': stale.refresh}, options: Options(headers: {'X-RideFlow-App': appClientId}));
        if (res.statusCode == 200 && res.data is Map) {
          final body = res.data as Map;
          final tokens = Tokens(body['access'] as String, (body['refresh'] ?? stale.refresh) as String);
          await session.save(tokens);
          return tokens;
        }
        await session.clear();
        return null;
      } on DioException catch (e) {
        // Network failure while refreshing: keep the session; the caller surfaces a network error.
        throw ApiException(0, 'network', detail: e.message);
      } finally {
        _refreshing = null;
      }
    }();
  }
}
