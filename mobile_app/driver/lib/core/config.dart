/// Build-time configuration (pass with `--dart-define`). No secrets live in the app.
///
/// API_BASE_URL defaults to the Android emulator's alias for the development machine's loopback
/// (10.0.2.2 -> host 127.0.0.1). A physical device needs the machine's reachable address instead.
class AppConfig {
  static const apiBaseUrl = String.fromEnvironment('API_BASE_URL', defaultValue: 'http://10.0.2.2:8010');

  /// Registered driver application of the operator (white-label app context, X-RideFlow-App).
  static const appClientId = String.fromEnvironment('APP_CLIENT_ID', defaultValue: 'demo-mukalla-driver');

  /// Shown only in debug builds on the sign-in screen, to make the target backend obvious.
  static const environmentLabel = String.fromEnvironment('ENV_LABEL', defaultValue: 'local');

  static Uri get wsEventsUri {
    final api = Uri.parse(apiBaseUrl);
    return api.replace(scheme: api.scheme == 'https' ? 'wss' : 'ws', path: '/ws/v1/events/');
  }

  /// Origin sent by the native WebSocket client: the API's own origin (Channels validates it against
  /// ALLOWED_HOSTS; native clients have no browser origin of their own).
  static String get apiOrigin {
    final api = Uri.parse(apiBaseUrl);
    return '${api.scheme}://${api.host}${api.hasPort ? ':${api.port}' : ''}';
  }
}
