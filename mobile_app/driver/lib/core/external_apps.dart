import 'package:url_launcher/url_launcher.dart';

/// Hands off to the phone's dialer and maps app. False means no app took it.
class ExternalApps {
  const ExternalApps();

  Future<bool> dial(String phone) => _open(Uri(scheme: 'tel', path: phone));

  /// Google Maps with the way to this point (from where the phone is). Any maps app if Google Maps isn't there.
  Future<bool> showOnMap(double lat, double lng) => directions(toLat: lat, toLng: lng);

  /// Google Maps with the route between two points; without a start it starts from the phone's location (D049).
  Future<bool> directions({double? fromLat, double? fromLng, required double toLat, required double toLng}) async {
    final to = '$toLat,$toLng';
    final query = {'api': '1', 'destination': to, 'travelmode': 'driving', if (fromLat != null && fromLng != null) 'origin': '$fromLat,$fromLng'};
    return await _open(Uri.https('www.google.com', '/maps/dir/', query)) || await _open(Uri.parse('geo:$to?q=$to'));
  }

  Future<bool> _open(Uri uri) async {
    try {
      return await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      return false;
    }
  }
}
