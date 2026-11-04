/// Uniform error from the RideFlow API ({"code": ..., "detail": ...} or {"code": "invalid", "errors": {...}}).
class ApiException implements Exception {
  ApiException(this.status, this.code, {this.detail, this.errors, this.reasons = const []});

  /// 0 = network / timeout (no HTTP response).
  final int status;
  final String code;
  final Object? detail;
  final Map<String, dynamic>? errors;

  /// Eligibility reasons when the backend refuses an action (e.g. `subscription_inactive`).
  final List<String> reasons;

  bool get isNetwork => status == 0;
  bool get isUnauthorized => status == 401;

  factory ApiException.fromResponse(int status, Object? body) {
    if (body is Map) {
      final map = body.cast<String, dynamic>();
      final code = (map['code'] ?? _codeForStatus(status)).toString();
      final detail = map['detail'];
      var reasons = <String>[];
      if (detail is Map && detail['reasons'] is List) {
        reasons = (detail['reasons'] as List).map((e) => e.toString()).toList();
      }
      final errors = map['errors'] is Map ? (map['errors'] as Map).cast<String, dynamic>() : null;
      return ApiException(status, code, detail: detail, errors: errors, reasons: reasons);
    }
    return ApiException(status, _codeForStatus(status));
  }

  /// First field error message, e.g. for showing under a form.
  String? fieldError(String field) {
    final value = errors?[field];
    if (value is List && value.isNotEmpty) return value.first.toString();
    if (value is String) return value;
    return null;
  }

  static String _codeForStatus(int status) => switch (status) {
        0 => 'network',
        401 => 'not_authenticated',
        403 => 'forbidden',
        404 => 'not_found',
        409 => 'conflict',
        429 => 'throttled',
        503 => 'service_unavailable',
        >= 500 => 'server_error',
        _ => 'error',
      };

  @override
  String toString() => 'ApiException($status, $code, $detail)';
}
