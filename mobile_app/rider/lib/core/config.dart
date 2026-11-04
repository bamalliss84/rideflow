/// Build-time configuration (pass with `--dart-define`). No secrets live in the app.
///
/// API_BASE_URL defaults to the Android emulator's alias for the development machine's loopback
/// (10.0.2.2 -> host 127.0.0.1). A physical device needs the machine's reachable address instead.
class AppConfig {
  static const apiBaseUrl = String.fromEnvironment('API_BASE_URL', defaultValue: 'http://10.0.2.2:8010');

  /// Registered rider application of the operator (white-label app context, X-RideFlow-App).
  static const appClientId = String.fromEnvironment('APP_CLIENT_ID', defaultValue: 'demo-mukalla-rider');

  /// XYZ tile address (`{z}/{x}/{y}`). Empty means no map data: stops and the driver still draw on a plain ground.
  static const mapTileUrl = String.fromEnvironment('MAP_TILE_URL');

  /// Credit the tile source's licence asks for, drawn on the map.
  static const mapAttribution = String.fromEnvironment('MAP_ATTRIBUTION', defaultValue: '© OpenStreetMap');

  /// In the night appearance, light tiles are darkened to match the app. A provider with its own dark style turns this off.
  static const mapDarken = bool.fromEnvironment('MAP_DARKEN', defaultValue: true);

  /// Address of a Photon place search. Empty means no search: the rider moves the map and names the place.
  static const geocoderUrl = String.fromEnvironment('GEOCODER_URL');

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
