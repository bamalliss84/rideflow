import 'package:url_launcher/url_launcher.dart';

/// Hands off to the phone's dialer and maps app. False means no app took it.
class ExternalApps {
  const ExternalApps();

  Future<bool> dial(String phone) => _open(Uri(scheme: 'tel', path: phone));

  Future<bool> showOnMap(double lat, double lng) async {
    final at = '$lat,$lng';
    return await _open(Uri.parse('geo:$at?q=$at')) || await _open(Uri.https('www.google.com', '/maps/search/', {'api': '1', 'query': at}));
  }

  Future<bool> _open(Uri uri) async {
    try {
      return await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      return false;
    }
  }
}
